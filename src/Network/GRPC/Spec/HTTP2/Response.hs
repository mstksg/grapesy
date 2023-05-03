{-# LANGUAGE OverloadedStrings #-}

-- | Deal with HTTP2 responses
--
-- Intended for qualified import.
--
-- > import Network.GRPC.Spec.HTTP2.Response (ResponseHeaders, ResponseTrailers)
-- > import Network.GRPC.Spec.HTTP2.Response qualified as Response
module Network.GRPC.Spec.HTTP2.Response (
    -- * Definition
    ResponseHeaders(..)
  , ResponseTrailers(..)
  , toTrailers
    -- * Parsing
  , parseHeaders
  , parseTrailers
  ) where

import Control.Monad.Except
import Control.Monad.State
import Data.ByteString qualified as BS.Strict
import Data.ByteString.Char8 qualified as BS.Strict.C8
import Data.CaseInsensitive qualified as CI
import Data.Either (fromRight)
import Data.Kind
import Data.List (intersperse)
import Data.SOP
import Generics.SOP qualified as SOP
import GHC.Generics qualified as GHC
import Network.HTTP.Types qualified as HTTP
import Text.Read (readMaybe)

import Network.GRPC.Spec
import Network.GRPC.Spec.Compression (CompressionId)
import Network.GRPC.Spec.Compression qualified as Compression
import Network.GRPC.Spec.CustomMetadata
import Network.GRPC.Spec.RPC
import Network.GRPC.Util.ByteString
import Network.GRPC.Util.HKD (IsHKD)
import Network.GRPC.Util.HKD qualified as HKD

{-------------------------------------------------------------------------------
  Definition
-------------------------------------------------------------------------------}

-- | Response headers
--
-- When we add this, should also update the parser.
data ResponseHeaders (f :: Type -> Type) = ResponseHeaders {
      compression       :: f (Maybe CompressionId)
    , acceptCompression :: f (Maybe [CompressionId])
    , customMetadata    :: f [CustomMetadata]
    }
  deriving stock (GHC.Generic)
  deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)

-- | Response trailers
--
-- Response trailers are a
-- [HTTP2 concept](https://datatracker.ietf.org/doc/html/rfc7540#section-8.1.3):
-- they are HTTP headers that are sent /after/ the content body. For example,
-- imagine the server is streaming a file that it's reading from disk; it could
-- use trailers to give the client an MD5 checksum when streaming is complete.
--
-- TODO: Custom metadata. When we add that, should also update the parser.
data ResponseTrailers (f :: Type -> Type) = ResponseTrailers {
      grpcStatus  :: f Word
    , grpcMessage :: f (Maybe String)
    }
  deriving stock (GHC.Generic)
  deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)

deriving instance (forall a. Show a => Show (f a)) => Show (ResponseHeaders  f)
deriving instance (forall a. Show a => Show (f a)) => Show (ResponseTrailers f)

uninitResponseHeaders :: ResponseHeaders (Either String)
uninitResponseHeaders = ResponseHeaders {
      compression       = Right Nothing
    , acceptCompression = Right Nothing
    , customMetadata    = Right []
    }

uninitResponseTrailers :: ResponseTrailers (Either String)
uninitResponseTrailers = ResponseTrailers {
      grpcStatus  = Left "Missing grpc-status"
    , grpcMessage = Right Nothing
    }

toTrailers :: ResponseTrailers I -> Trailers
toTrailers trailers = Trailers {
      trailersGrpcStatus  = unI $ grpcStatus  trailers
    , trailersGrpcMessage = unI $ grpcMessage trailers
    }

{-------------------------------------------------------------------------------
  Response headers

  TODO: We should attempt to be more lenient in our parsing here, and throw
  fewer errors. Perhaps have an @Invalid@ constructor or something, so that
  we can mark incoming headers that were not valid, but still give them to the
  user, but then throw an error if we try to /send/ those.

  TODO: Related to the above, the spec says: "Implementations MUST accept padded
  and un-padded values and should emit un-padded values." We don't currently do
  this for incoming headers.
-------------------------------------------------------------------------------}

newtype HeaderParser s a = WrapHeaderParser {
      unwrapHeaderParser :: StateT (s (Either String)) (Except String) a
    }
  deriving newtype (
      Functor
    , Applicative
    , Monad
    , MonadError String
    , MonadState (s (Either String))
    )

runHeaderParser ::
     IsHKD s
  => s (Either String)
  -> HeaderParser s () -> Either String (s I)
runHeaderParser uninit =
      (>>= HKD.hsequence)
    . runExcept
    . flip execStateT uninit
    . unwrapHeaderParser

-- | Parse response headers
parseHeaders ::
     IsRPC rpc
  => rpc
  -> [HTTP.Header]
  -> Either String (ResponseHeaders I)
parseHeaders rpc =
      runHeaderParser uninitResponseHeaders
    . mapM_ parseHeader
  where
    -- HTTP2 header names are always lowercase, and must be ASCII.
    -- <https://datatracker.ietf.org/doc/html/rfc7540#section-8.1.2>
    parseHeader :: HTTP.Header -> HeaderParser ResponseHeaders ()
    parseHeader (name, value)
      | name == "content-type" = do
          let accepted = [
                  "application/grpc"
                , "application/grpc+" <> serializationFormat rpc
                ]
          unless (value `elem` accepted) $
            throwError $ concat [
                "Unexpected content-type "
              , BS.Strict.C8.unpack value
              , "; expected one of "
              , mconcat . intersperse ", " . map BS.Strict.C8.unpack $ accepted
              , "'"
              ]

      | name == "grpc-encoding"
      = modify $ \partial -> partial{
            compression = Right $ Just $ Compression.deserializeId value
          }

      | name == "grpc-accept-encoding"
      = modify $ \partial -> partial{
            acceptCompression = Right . Just $
              map (Compression.deserializeId . strip) $
                BS.Strict.splitWith (== ascii ',') value
          }

      | "grpc-" `BS.Strict.isPrefixOf` CI.foldedCase name
      = throwError $ "Reserved header: " ++ show (name, value)

      | "-bin" `BS.Strict.isSuffixOf` CI.foldedCase name
      = case safeHeaderName (BS.Strict.dropEnd 4 $ CI.foldedCase name) of
          Just name' ->
            modify $ \partial -> partial{
                customMetadata = Right $
                    BinaryHeader name' value
                  : fromRight [] (customMetadata partial)
              }
          _otherwise ->
            throwError $ "Invalid custom binary header: " ++ show (name, value)

      | otherwise
      = case ( safeHeaderName (CI.foldedCase name)
             , safeAsciiValue value
             ) of
          (Just name', Just value') ->
            modify $ \partial -> partial{
                customMetadata = Right $
                    AsciiHeader name' value'
                  : fromRight [] (customMetadata partial)
              }
          _otherwise ->
            throwError $ "Invalid custom ASCII header: " ++ show (name, value)

-- | Parse response trailers
--
-- TODO: We don't currently parse the status message. We should find an example
-- server that gives us some, so that we can test.
parseTrailers :: [HTTP.Header] -> Either String (ResponseTrailers I)
parseTrailers =
      runHeaderParser uninitResponseTrailers
    . mapM_ parseHeader
  where
    parseHeader :: HTTP.Header -> HeaderParser ResponseTrailers ()
    parseHeader (name, value)
      | name == "grpc-status"
      = case readMaybe (BS.Strict.C8.unpack value) of
          Nothing -> throwError $ "Invalid status: " ++ show value
          Just v  -> modify $ \partial -> partial{
                         grpcStatus = Right v
                       }

      | otherwise
      = throwError $ "Unrecognized header: " ++ show (name, value)


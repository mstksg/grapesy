{-# LANGUAGE OverloadedStrings #-}

-- | Functionality shared between requests and responses
--
-- The following headers are used both in requests and in responses:
--
-- * @Content-Type@
-- * @Message-Encoding@
-- * @Message-Accept-Encoding@
-- * @Custom-Metadata@ (see "Network.GRPC.Spec.CustomMetadata")
--
-- Intended for unqualified import.
module Network.GRPC.Spec.Common (
    -- * Construction
    buildContentType
  , buildMessageEncoding
  , buildMessageAcceptEncoding
    -- * Parsing
  , parseContentType
  , parseMessageEncoding
  , parseMessageAcceptEncoding
  ) where

import Control.Monad.Except
import Data.ByteString qualified as BS.Strict
import Data.Foldable (toList)
import Data.List (intersperse)
import Data.List.NonEmpty (NonEmpty(..))
import Data.Proxy
import Network.HTTP.Types qualified as HTTP

import Network.GRPC.Spec.Compression
import Network.GRPC.Spec.RPC
import Network.GRPC.Util.ByteString
import Network.GRPC.Util.Partial

{-------------------------------------------------------------------------------
  > Content-Type →
  >   "content-type"
  >   "application/grpc"
  >   [("+proto" / "+json" / {custom})]
-------------------------------------------------------------------------------}

buildContentType :: IsRPC rpc => Proxy rpc -> HTTP.Header
buildContentType proxy = (
      "content-type"
    , "application/grpc+" <> serializationFormat proxy
    )

parseContentType ::
     (MonadError String m, IsRPC rpc)
  => Proxy rpc
  -> HTTP.Header
  -> m ()
parseContentType proxy hdr =
    expectHeaderValue hdr $ [
        "application/grpc"
      , "application/grpc+octet-stream"
      , "application/grpc+" <> serializationFormat proxy
      ]

{-------------------------------------------------------------------------------
  > Message-Encoding → "grpc-encoding" Content-Coding
  > Content-Coding → "identity" / "gzip" / "deflate" / "snappy" / {custom}
-------------------------------------------------------------------------------}

buildMessageEncoding :: CompressionId -> HTTP.Header
buildMessageEncoding compr = (
      "grpc-encoding"
    , serializeCompressionId compr
    )

parseMessageEncoding ::
     MonadError String m
  => HTTP.Header
  -> m CompressionId
parseMessageEncoding (_name, value) =
    return $ deserializeCompressionId value

{-------------------------------------------------------------------------------
  > Message-Accept-Encoding →
  >   "grpc-accept-encoding" Content-Coding *("," Content-Coding)
-------------------------------------------------------------------------------}

buildMessageAcceptEncoding :: NonEmpty CompressionId -> HTTP.Header
buildMessageAcceptEncoding compr = (
      "grpc-accept-encoding"
    , mconcat . intersperse "," . map serializeCompressionId $ toList compr
    )

parseMessageAcceptEncoding ::
     MonadError String m
  => HTTP.Header
  -> m (NonEmpty CompressionId)
parseMessageAcceptEncoding (_name, value) =
      expectAtLeastOne
    . map (deserializeCompressionId . strip)
    . BS.Strict.splitWith (== ascii ',')
    $ value

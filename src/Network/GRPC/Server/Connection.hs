{-# LANGUAGE OverloadedStrings #-}

-- | Connection to a client
--
-- This is not part of the library's public API.
--
-- Intended for qualified import.
--
-- > import Network.GRPC.Server.Connection (Connection(..), withConnection)
-- > import Network.GRPC.Server.Connection qualified as Connection
module Network.GRPC.Server.Connection (
    Connection(..)
  , withConnection
    -- * Query
  , path
  ) where

import Data.ByteString qualified as Strict (ByteString)
import Data.ByteString.Builder (Builder)
import Data.ByteString.Builder qualified as Builder
import Data.Maybe (fromMaybe)
import Network.HTTP.Types qualified as HTTP
import Network.HTTP2.Server qualified as HTTP2

import Network.GRPC.Server.Context
import Network.GRPC.Spec
import Network.GRPC.Util.Session (ConnectionToClient(..))

{-------------------------------------------------------------------------------
  Connection API

  Unlike 'Network.GRPC.Client.Connection.Connection', this connection is
  short-lived (@http2@ gives us each request separately, without identifying
  which requests come from the same client).

  Conversely, on the client side, we maintain some meta information (such as
  supported compression algorithms) about the connection to the server. The
  equivalent on the server side is 'Network.GRPC.Server.Context.ServerContext',
  but this is maintained for the full lifetime of the server.
-------------------------------------------------------------------------------}

-- | Open connection to a client (for one specific request)
data Connection = Connection {
      connectionContext  :: ServerContext
    , connectionResource :: ResourceHeaders
    , connectionClient   :: ConnectionToClient
    }

{-------------------------------------------------------------------------------
  Setup a new connection
-------------------------------------------------------------------------------}

withConnection :: ServerContext -> (Connection -> IO ()) -> HTTP2.Server
withConnection context k request _aux respond' = do
    -- TODO: We should log these out-of-spec responses
    case getResourceHeaders request of
      Left  err             -> respond $ outOfSpecResponse err
      Right resourceHeaders -> do
        let conn :: Connection
            conn = Connection{
                connectionContext  = context
              , connectionResource = resourceHeaders
              , connectionClient   = connectionToClient
              }

        k conn
  where
    connectionToClient :: ConnectionToClient
    connectionToClient = ConnectionToClient{request, respond}

    -- gRPC does not make use of push promises
    respond :: HTTP2.Response -> IO ()
    respond = flip respond' []

{-------------------------------------------------------------------------------
  Query
-------------------------------------------------------------------------------}

path :: Connection -> Path
path = resourcePath . connectionResource

{-------------------------------------------------------------------------------
  Pseudo headers
-------------------------------------------------------------------------------}

getResourceHeaders :: HTTP2.Request -> Either OutOfSpecError ResourceHeaders
getResourceHeaders req =
    case parseResourceHeaders (rawResourceHeaders req) of
      Left (InvalidPath   x) -> Left $ bad "invalid path"   x
      Left (InvalidMethod x) -> Left $ httpMethodNotAllowed x
      Right hdrs             -> return hdrs
  where
    bad :: Builder -> Strict.ByteString -> OutOfSpecError
    bad msg arg = httpBadRequest $ mconcat [
          msg
        , ": "
        , Builder.byteString arg
        ]

rawResourceHeaders :: HTTP2.Request -> RawResourceHeaders
rawResourceHeaders req = RawResourceHeaders {
      rawPath   = fromMaybe "" $ HTTP2.requestPath   req
    , rawMethod = fromMaybe "" $ HTTP2.requestMethod req
    }

{-------------------------------------------------------------------------------
  Out-of-spec errors
-------------------------------------------------------------------------------}

-- | The request did not conform to the gRPC specification
--
-- The gRPC spec mandates that we /always/ return HTTP 200 OK, but it does
-- not explicitly say what to do when the request is mal-formed (not
-- conform the gRPC specification). We choose to return HTTP errors in
-- this case.
--
-- See <https://datatracker.ietf.org/doc/html/rfc7231#section-6.5> for
-- a discussion of the HTTP error codes.
--
-- Testing out-of-spec errors can be bit awkward. One option is @curl@:
--
-- > curl --verbose --http2 --http2-prior-knowledge http://localhost:50051/
data OutOfSpecError = OutOfSpecError {
      outOfSpecStatus  :: HTTP.Status
    , outOfSpecHeaders :: [HTTP.Header]
    , outOfSpecBody    :: Builder
    }

outOfSpecResponse :: OutOfSpecError -> HTTP2.Response
outOfSpecResponse err =
    HTTP2.responseBuilder
      (outOfSpecStatus  err)
      (outOfSpecHeaders err)
      (outOfSpecBody    err)

-- | 405 Method Not Allowed
--
-- <https://datatracker.ietf.org/doc/html/rfc7231#section-6.5.5>
-- <https://datatracker.ietf.org/doc/html/rfc7231#section-7.4.1>
httpMethodNotAllowed :: Strict.ByteString -> OutOfSpecError
httpMethodNotAllowed method = OutOfSpecError {
      outOfSpecStatus  = HTTP.methodNotAllowed405
    , outOfSpecHeaders = [("Allow", "POST")]
    , outOfSpecBody    = mconcat [
          "Unexpected :method " <> Builder.byteString method <> ".\n"
        , "The only method supported by gRPC is POST.\n"
        ]
    }

-- | 400 Bad Request
--
-- <https://datatracker.ietf.org/doc/html/rfc7231#section-6.5.1>
httpBadRequest :: Builder -> OutOfSpecError
httpBadRequest body = OutOfSpecError {
      outOfSpecStatus  = HTTP.badRequest400
    , outOfSpecHeaders = []
    , outOfSpecBody    = body
    }

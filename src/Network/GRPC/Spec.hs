-- | Pure implementation of the gRPC spec
--
-- Most code will not need to use this module directly.
--
-- Intended for unqualified import.
module Network.GRPC.Spec (
    -- * RPC
    IsRPC(..)
    -- ** Instances
  , Protobuf
  , BinaryRpc
    -- ** Serialization
  , parseInput
  , parseOutput
  , buildInput
  , buildOutput
    -- * Streaming types
  , StreamingType(..)
  , SupportsStreamingType
  , HasStreamingType(..)
    -- ** Handlers
  , HandlerFor
  , NonStreamingHandler(..)
  , ClientStreamingHandler(..)
  , ServerStreamingHandler(..)
  , BiDiStreamingHandler(..)
    -- ** Execution
  , nonStreaming
  , clientStreaming
  , serverStreaming
  , biDiStreaming
    -- ** Construction
  , mkNonStreaming
  , mkClientStreaming
  , mkServerStreaming
  , mkBiDiStreaming
    -- * Compression
  , CompressionId(..)
  , Compression(..)
    -- ** Compression algorithms
  , noCompression
  , gzip
  , allSupportedCompression
    -- * Requests
  , RequestHeaders(..)
    -- ** Parameters
  , CallParams(..)
    -- ** Pseudo-headers
  , PseudoHeaders(..)
  , ServerHeaders(..)
  , ResourceHeaders(..)
  , Path(..)
  , Address(..)
  , Scheme(..)
  , Method(..)
  , rpcPath
    -- ** Serialization
  , RawResourceHeaders(..)
  , InvalidResourceHeaders(..)
  , buildResourceHeaders
  , parseResourceHeaders
    -- ** Headers
  , buildRequestHeaders
  , parseRequestHeaders
    -- ** Timeouts
  , Timeout(..)
  , TimeoutValue(..)
  , TimeoutUnit(..)
  , timeoutToMicro
    -- * Responses
    -- ** Headers
  , ResponseHeaders(..)
  , buildResponseHeaders
  , parseResponseHeaders
    -- ** Trailers
  , ProperTrailers(..)
  , TrailersOnly(..)
  , parseProperTrailers
  , parseTrailersOnly
  , buildProperTrailers
  , buildTrailersOnly
    -- *** Status
  , GrpcStatus(..)
  , GrpcError(..)
    -- *** Classificaiton
  , GrpcException(..)
  , grpcExceptionToTrailers
  , grpcExceptionFromTrailers
    -- * Metadata
  , CustomMetadata(..)
  , HeaderName(..)
  , BinaryValue(..)
  , AsciiValue(..)
  , NoMetadata(..)
  , customHeaderName
  , parseCustomMetadata
  , buildCustomMetadata
  , safeHeaderName
  , safeAsciiValue
  ) where

import Network.GRPC.Spec.Call
import Network.GRPC.Spec.Compression
import Network.GRPC.Spec.CustomMetadata
import Network.GRPC.Spec.LengthPrefixed
import Network.GRPC.Spec.PseudoHeaders
import Network.GRPC.Spec.Request
import Network.GRPC.Spec.Response
import Network.GRPC.Spec.RPC
import Network.GRPC.Spec.RPC.Binary
import Network.GRPC.Spec.RPC.Protobuf
import Network.GRPC.Spec.RPC.StreamType
import Network.GRPC.Spec.Status
import Network.GRPC.Spec.Timeout

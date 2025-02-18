-- | Public 'Compression' API
--
-- Intended for unqualified import.
--
-- > import Network.GRPC.Common.Compression (Compression(..))
-- > import Network.GRPC.Common.Compression qualified as Compr
module Network.GRPC.Common.Compression (
    -- * Definition
    Compression(..)
  , CompressionId(..)
    -- * Standard compression schemes
  , noCompression
  , gzip
  , allSupportedCompression
    -- * Negotation
  , Negotation(..)
  , getSupported
    -- ** Specific negotation strategies
  , none
  , require
  , chooseFirst
    -- ** Exceptions
  , CompressionNegotationFailed(..)
  ) where

import Control.Exception
import Data.Default
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty(..))
import Data.List.NonEmpty qualified as NE
import Data.Map (Map)
import Data.Map qualified as Map
import Text.Show.Pretty

import Network.GRPC.Spec

{-------------------------------------------------------------------------------
  Negotation
-------------------------------------------------------------------------------}

-- | Compression negotation
data Negotation = Negotation {
      -- | Which algorithms should be offered (in this order) to the peer?
      offer :: NonEmpty CompressionId

      -- | Choose compression algorithm
      --
      -- We will run this only once per open connection, when the server first
      -- tells us their list of supported compression algorithms. Unless
      -- compression negotation has taken place, no compression should be used.
    , choose ::
           NonEmpty CompressionId
        -> Either CompressionNegotationFailed Compression

      -- | All supported compression algorithms
    , supported :: Map CompressionId Compression
    }

-- | Map 'CompressionId' to 'Compression' for supported algorithms
getSupported :: Negotation -> CompressionId -> Maybe Compression
getSupported compr cid = Map.lookup cid (supported compr)

instance Default Negotation where
  def = chooseFirst allSupportedCompression

-- | Disable all compression
none :: Negotation
none = require noCompression

-- | Insist on the specified algorithm
require :: Compression -> Negotation
require = chooseFirst . (:| [])

-- | Choose the first algorithm that appears in the list of client supported
chooseFirst :: NonEmpty Compression -> Negotation
chooseFirst ourSupported = Negotation {
      offer =
        fmap compressionId ourSupported
    , choose = \serverSupported ->
        let isSupported :: Compression -> Bool
            isSupported = (`elem` serverSupported) . compressionId
        in case NE.filter isSupported ourSupported of
             c:_ -> Right c
             []  -> Left $ CompressionNegotationFailed serverSupported
    , supported =
        Map.fromList $
          map (\c -> (compressionId c, c)) (toList ourSupported)
    }

{-------------------------------------------------------------------------------
  Exceptions
-------------------------------------------------------------------------------}

-- | Negotation failed
--
-- Unlike 'CompressionException', this is /not/ indicative of a misbehaving
-- peer. It does however mean that we probably cannot talk to this peer.
data CompressionNegotationFailed =
    -- | We don't support any of the compression algorithms listed by the peer
    CompressionNegotationFailed (NonEmpty CompressionId)
  deriving stock (Show)
  deriving anyclass (Exception)

instance PrettyVal CompressionNegotationFailed where
  prettyVal = String . show

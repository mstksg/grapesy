module Demo.Client.API.Protobuf.Pipes.RouteGuide (
    listFeatures
  , recordRoute
  , routeChat
  ) where

import Control.Concurrent.Async
import Data.Default
import Data.Proxy
import Pipes hiding (Proxy)
import Pipes.Prelude qualified as Pipes
import Pipes.Safe

import Network.GRPC.Client
import Network.GRPC.Client.StreamType.Pipes
import Network.GRPC.Common.StreamElem (StreamElem(..))

import Proto.RouteGuide

import Demo.Common.Logging

{-------------------------------------------------------------------------------
  routeguide.RouteGuide

  We do not include the 'getFeature' method, as it does not do any streaming.
-------------------------------------------------------------------------------}

listFeatures :: Connection -> Rectangle -> IO ()
listFeatures conn r = runSafeT . runEffect $
    (prod >>= logMsg) >-> Pipes.mapM_ logMsg
  where
    prod :: Producer' Feature (SafeT IO) ()
    prod = serverStreaming conn def (Proxy @(Protobuf RouteGuide "listFeatures")) r

recordRoute ::
     Connection
  -> Producer' (StreamElem () Point) (SafeT IO) ()
  -> IO ()
recordRoute conn ps = runSafeT . runEffect $
    ps >-> (cons >>= logMsg)
  where
    cons :: Consumer' (StreamElem () Point) (SafeT IO) RouteSummary
    cons = clientStreaming conn def (Proxy @(Protobuf RouteGuide "recordRoute"))

routeChat ::
     Connection
  -> Producer' (StreamElem () RouteNote) IO ()
  -> IO ()
routeChat conn ns =
    biDiStreaming conn def (Proxy @(Protobuf RouteGuide "routeChat")) aux
  where
    aux ::
         Consumer' (StreamElem () RouteNote) IO ()
      -> Producer' RouteNote IO ()
      -> IO ()
    aux cons prod =
        concurrently_
          (runEffect $ ns >-> cons)
          (runEffect $ (prod >>= logMsg) >-> Pipes.mapM_ logMsg)

module Demo.Common.Logging (
    threadSafeTracer
  , logMsg
  ) where

import Control.Monad.IO.Class
import Control.Tracer
import GHC.IO (unsafePerformIO)

import Debug.Concurrent

tracingLock :: MVar ()
{-# NOINLINE tracingLock #-}
tracingLock = unsafePerformIO $ newMVar ()

threadSafeTracer :: Tracer IO String
threadSafeTracer = arrow $ emit $ \msg ->
    withMVar tracingLock $ \() -> putStrLn msg

logMsg :: (MonadIO m, Show a) => a -> m ()
logMsg = liftIO . traceWith threadSafeTracer . show
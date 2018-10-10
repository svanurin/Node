module Enecuum.Legacy.Service.Network.TCP.Server (runServer) where

import           Control.Concurrent (forkFinally)
import           Control.Monad
import           Enecuum.Prelude
import           Network            (PortID (..), listenOn)
import           Network.Socket

-- | Run TCP server.
runServer :: PortNumber -> (Socket -> IO ()) -> IO ()
runServer aPortNumber aPlainHandler = withSocketsDo $ do
    sock <- listenOn $ PortNumber aPortNumber
    forever $ do
        (conn, _) <- accept sock
        void $ forkFinally (aPlainHandler conn) (\_ -> close conn)

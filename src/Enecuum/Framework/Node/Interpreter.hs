{-# LANGUAGE TypeInType #-}
{-# LANGUAGE PackageImports #-}

module Enecuum.Framework.Node.Interpreter where

import           Enecuum.Prelude
import qualified "rocksdb-haskell" Database.RocksDB       as Rocks

import           Control.Concurrent.STM.TChan
import qualified Data.Map                                         as M
import           Enecuum.Core.HGraph.Internal.Impl
import qualified Enecuum.Core.Types                               as D
import qualified Enecuum.Core.Lens                                as Lens
import           Enecuum.Core.HGraph.Interpreters.IO
import qualified Enecuum.Core.Interpreters                        as Impl
import qualified Enecuum.Core.Language                            as L
import qualified Enecuum.Framework.Domain.Networking              as D
import qualified Enecuum.Framework.Handler.Network.Interpreter    as Net
import qualified Enecuum.Framework.Networking.Internal.Connection as Con
import qualified Enecuum.Framework.Networking.Interpreter         as Impl
import qualified Enecuum.Framework.Language                       as L
import qualified Enecuum.Framework.RLens                          as RLens
import qualified Enecuum.Framework.Runtime                        as R
import           Enecuum.Framework.Runtime                        (NodeRuntime)
import qualified Enecuum.Framework.State.Interpreter              as Impl
import qualified Enecuum.Core.Types.Logger as Log
import qualified Network.Socket                                   as S
import           Enecuum.Framework.Networking.Internal.Connection (ServerHandle (..))

runDatabase :: R.DBHandle -> L.DatabaseL db a -> IO a
runDatabase dbHandle action = do
    void $ takeMVar $ dbHandle ^. RLens.mutex
    res <- Impl.runDatabaseL (dbHandle ^. RLens.db) action
    putMVar (dbHandle ^. RLens.mutex) ()
    pure res

-- | Interpret NodeL.
interpretNodeL :: NodeRuntime -> L.NodeF a -> IO a
interpretNodeL nodeRt (L.EvalStateAtomically statefulAction next) =
    next <$> atomically (Impl.runStateL nodeRt statefulAction)

interpretNodeL _      (L.EvalGraphIO gr act next       ) = next <$>  (runHGraphIO gr act)

interpretNodeL nodeRt (L.EvalNetworking networking next) = next <$>  (Impl.runNetworkingL nodeRt networking)

interpretNodeL nodeRt (L.EvalCoreEffectNodeF coreEffects next) =
    next <$>  (Impl.runCoreEffect (nodeRt ^. RLens.coreRuntime) coreEffects)

interpretNodeL nodeRt (L.OpenTcpConnection addr initScript next) =
    next <$> openConnection nodeRt (nodeRt ^. RLens.tcpConnects) addr initScript

interpretNodeL nodeRt (L.OpenUdpConnection addr initScript next) =
    next <$> openConnection nodeRt (nodeRt ^. RLens.udpConnects) addr initScript

interpretNodeL nodeRt (L.CloseTcpConnection (D.Connection addr) next) =
    next <$> closeConnection (nodeRt ^. RLens.tcpConnects) addr

interpretNodeL nodeRt (L.CloseUdpConnection (D.Connection addr) next) =
    next <$> closeConnection (nodeRt ^. RLens.udpConnects) addr

interpretNodeL nodeRt (L.InitDatabase cfg next) = do
    let path = cfg ^. Lens.path
    let opts = Rocks.defaultOptions
            { Rocks.createIfMissing = cfg ^. Lens.options . Lens.createIfMissing
            , Rocks.errorIfExists   = cfg ^. Lens.options . Lens.errorIfExists
            }
    -- TODO: FIXME: check what exceptions may be thrown here and handle it correctly.
    -- TODO: ResourceT usage.
    eDb <- try $ Rocks.open path opts
    case eDb of
        Left (err :: SomeException) -> pure $ next $ Left $ D.DBError D.SystemError (show err)
        Right db -> do
            -- DB single entry point: worker.
            mutex <- newMVar ()
            let dbHandle = R.DBHandle db mutex
            -- Registering DB
            atomically $ modifyTVar (nodeRt ^. RLens.databases) (M.insert path dbHandle)
            pure $ next $ Right $ D.Storage path

interpretNodeL nodeRt (L.EvalDatabase storage action next) = do
    dbs <- readTVarIO $ nodeRt ^. RLens.databases
    case M.lookup (storage ^. Lens.path) dbs of
        Nothing       -> error $ "Impossible: DB is not registered: " +|| storage ^. Lens.path ||+ "."
        Just dbHandle -> do
            r <- runDatabase dbHandle action
            pure $ next r

interpretNodeL _ (L.NewGraph next) = next <$> initHGraph

type F f a = a -> f a

class ConnectsLens a where
    connectsLens
        :: Functor f
        => F f (TMVar (Map D.Address (D.ConnectionVar a)))
        -> NodeRuntime
        -> f NodeRuntime

instance ConnectsLens D.Udp where
    connectsLens = RLens.udpConnects

instance ConnectsLens D.Tcp where
    connectsLens = RLens.tcpConnects

closeConnection
    :: Con.NetworkConnection protocol
    => TMVar (Map D.Address (D.ConnectionVar protocol)) -> D.Address -> IO ()
closeConnection connectsRef addr = do
    trace @String "[closeConnection-high-level] closing high-level conn. Taking connections" $ pure ()
    conns <- atomically $ takeTMVar connectsRef
    case M.lookup addr conns of
        Nothing -> do
            trace @String "[closeConnection-high-level] high-level conn not registered. Releasing connections" $ pure ()
            atomically $ putTMVar connectsRef conns
        Just conn -> do
            trace @String "[closeConnection-high-level] closing low-level conn" $ pure ()
            Con.close conn
            trace @String "[closeConnection-high-level] deleting conn, releasing connections" $ pure ()
            atomically $ putTMVar connectsRef $ M.delete addr conns



-- TODO: need to delete old connection if it's dead.
openConnection nodeRt connectsRef addr initScript = do
    trace @String "[openConnection-high-level] opening high-level conn. Taking connections" $ pure ()
    conns <- atomically $ takeTMVar connectsRef
    if M.member addr conns
        then do
            trace @String "[openConnection-high-level] old conn found, releasing connections" $ pure ()
            atomically $ putTMVar connectsRef conns
            pure Nothing
        else do
            trace @String "[openConnection-high-level] none old conn. Creating new" $ pure ()
            m <- newTVarIO mempty
            _ <- Net.runNetworkHandlerL m initScript

            handlers <- readTVarIO m

            trace @String "[openConnection-high-level] opening low-level conn" $ pure ()
            newCon   <- Con.openConnect
                addr
                ((\f a b -> runNodeL nodeRt $ f a b) <$> handlers)
            case newCon of
                Just justCon -> do
                    trace @String "[openConnection-high-level] low-level conn opened. Registering." $ pure ()
                    let newConns = M.insert addr justCon conns
                    trace @String "[openConnection-high-level] releasing connections" $ pure ()
                    atomically $ putTMVar connectsRef newConns
                    pure $ Just $ D.Connection addr
                _ -> do
                    trace @String "[openConnection-high-level] low-level conn failed to open. Releasing connections" $ pure ()
                    atomically $ putTMVar connectsRef conns
                    pure Nothing


-- This is all wrong, including invalid usage of TChan and other issues.
-- making it IO temp (which is even more wrong), but it needs to be deleted.
setServerChan :: TVar (Map S.PortNumber ServerHandle) -> S.PortNumber -> TChan D.ServerComand -> IO ()
setServerChan servs port chan = do
    serversMap <- atomically $ readTVar servs
    whenJust (serversMap ^. at port) Con.stopServer
    atomically $ modifyTVar servs (M.insert port (OldServerHandle chan))

-- | Runs node language. Runs interpreters for the underlying languages.
runNodeL :: NodeRuntime -> L.NodeL a -> IO a
runNodeL nodeRt = foldFree (interpretNodeL nodeRt)

logError' :: NodeRuntime -> Log.Message -> IO ()
logError' nodeRt = runNodeL nodeRt . L.logError

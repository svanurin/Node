module Enecuum.Assets.Nodes.Routing.RoutingHandlers where

import qualified Enecuum.Assets.Nodes.Address     as A
import qualified Enecuum.Assets.Nodes.Messages    as M
import           Enecuum.Assets.Nodes.Methods
import qualified Enecuum.Domain                   as D
import qualified Enecuum.Language                 as L
import           Enecuum.Prelude
import           Enecuum.Research.ChordRouteMap
import           Enecuum.Assets.Nodes.Routing.Messages
import qualified Data.Sequence as Seq
import qualified Data.Set      as Set
import           Enecuum.Assets.Nodes.Routing.RuntimeData
import           Enecuum.Assets.Nodes.Routing.RoutingWorker
import           Enecuum.Assets.Nodes.Routing.MessageHandling

udpRoutingHandlers :: RoutingRuntime -> L.NetworkHandlerL D.Udp L.NodeL ()
udpRoutingHandlers routingRuntime = do
    L.handler $ acceptHello             routingRuntime
    L.handler $ acceptConnectResponse   routingRuntime
    L.handler $ acceptNextForYou        routingRuntime
    L.handler $ acceptHelloFromBn       routingRuntime

rpcRoutingHandlers :: RoutingRuntime -> L.RpcHandlerL L.NodeL ()
rpcRoutingHandlers routingRuntime = do
    L.method rpcPingPong
    L.method $ connectMapRequest routingRuntime

-- answer to the questioner who is successor for me
acceptNextForYou :: RoutingRuntime -> NextForYou -> D.Connection D.Udp -> L.NodeL ()
acceptNextForYou routingRuntime (NextForYou senderAddress) conn = do
    L.close conn
    connects <- getConnects routingRuntime
    let mAddress = snd <$> findNextForHash (routingRuntime ^. myNodeId) connects
    whenJust mAddress $ \address -> void $ L.notify senderAddress address


acceptHelloFromBn :: RoutingRuntime -> HelloToBnResponce -> D.Connection D.Udp -> L.NodeL ()
acceptHelloFromBn routingRuntime bnHello con = do
    L.close con
    when (verifyHelloToBnResponce bnHello) $
        L.writeVarIO (routingRuntime ^. hostAddress) $ Just (bnHello ^. hostAddress)

-- | Processing of messages forwarded to maintain the integrity of the network structure
--   clarifying the predecessor and successor relationship
acceptHello :: RoutingRuntime -> RoutingHello -> D.Connection D.Udp -> L.NodeL ()
acceptHello routingRuntime routingHello con = do
    L.close con
    when (verifyRoutingHello routingHello) $ do
        connects <- getConnects routingRuntime
        let senderAddress = routingHello ^. nodeAddress
        let senderNodeId  = senderAddress ^. A.nodeId
        let nextAddres    = nextForHello (routingRuntime ^. myNodeId) senderNodeId connects
        whenJust nextAddres $ \reciverAddress ->
            void $ L.notify (A.getUdpAddress reciverAddress) routingHello
        
        L.modifyVarIO
            (routingRuntime ^. connectMap)
            (addToMap senderNodeId senderAddress)

acceptConnectResponse :: RoutingRuntime -> A.NodeAddress -> D.Connection D.Udp -> L.NodeL ()
acceptConnectResponse routingRuntime address con = do
    L.close con
    -- if this address is not mine, then add it
    unlessM (itIsMyAddress routingRuntime address) $
        L.modifyVarIO (routingRuntime ^. connectMap) (addToMap (address ^. A.nodeId) address)

itIsMyAddress :: RoutingRuntime -> A.NodeAddress -> L.NodeL Bool
itIsMyAddress routingRuntime address = do
    myAddress <- getMyNodeAddress routingRuntime
    pure $ Just address == myAddress

connectMapRequest :: RoutingRuntime -> M.ConnectMapRequest -> L.NodeL [A.NodeAddress]
connectMapRequest nodeRuntime _ =
    -- return all known connections
    (snd <$>) . fromChordRouteMap <$> L.readVarIO (nodeRuntime ^. connectMap)

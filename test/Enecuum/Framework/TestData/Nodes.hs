{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Enecuum.Framework.TestData.Nodes where

import Enecuum.Prelude

import qualified Data.Aeson                    as A
import qualified Data.ByteString.Lazy          as BS

import qualified Enecuum.Domain                as D
import qualified Enecuum.Language              as L
import qualified Enecuum.Framework.Lens        as Lens
import qualified Enecuum.API                   as API

bootNodeAddr, masterNode1Addr :: D.NodeAddress
bootNodeAddr = "boot node addr"
masterNode1Addr = "master node 1 addr"

bootNodeTag, masterNodeTag :: D.NodeTag
bootNodeTag = "bootNode"
masterNodeTag = "masterNode"

localNetwork = error "localNetwork"

-- Just dummy types
data GetNeighboursRequest = GetNeighboursRequest
  deriving (Show, Eq, Generic, ToJSON, FromJSON)

data GetHashIDRequest = GetHashIDRequest
  deriving (Show, Eq, Generic, ToJSON, FromJSON)
newtype GetHashIDResponse = GetHashIDResponse Text
  deriving (Show, Eq, Generic, Newtype, ToJSON, FromJSON)

instance D.RpcMethod () GetHashIDRequest GetHashIDResponse where
  toRpcRequest _ = D.RpcRequest . A.encode
  fromRpcResponse _ _ = Just $ GetHashIDResponse "1"

newtype HelloRequest1  = HelloRequest1 { helloMessage :: Text }
  deriving (Show, Eq, Generic, ToJSON, FromJSON)
newtype HelloResponse1 = HelloResponse1 { ackMessage :: Text }
  deriving (Show, Eq, Generic, Newtype, ToJSON, FromJSON)

instance D.RpcMethod () HelloRequest1 HelloResponse1 where
  toRpcRequest _ req = D.RpcRequest $ A.encode req
  fromRpcResponse _ (D.RpcResponse raw) = A.decode raw

data HelloRequest2 = HelloRequest2 Text
  deriving (Show, Eq, Generic, ToJSON, FromJSON)

data AcceptConnectionRequest = AcceptConnectionRequest
  deriving (Show, Eq, Generic, ToJSON, FromJSON)

simpleBootNodeDiscovery :: Eff L.NetworkModel D.NodeAddress
simpleBootNodeDiscovery = do
  mbBootNodeAddr <- fmap unpack <$> (L.multicastRequest localNetwork 10.0 $ API.FindNodeByTagRequest bootNodeTag)
  case mbBootNodeAddr of
    Nothing   -> pure bootNodeAddr  -- Temp
    Just addr -> pure addr

acceptHello1 :: HelloRequest1 -> Eff L.NodeModel ()
acceptHello1 (HelloRequest1 msg) = error $ "Accepting HelloRequest1: " ++ show msg

acceptHello2 :: HelloRequest2 -> Eff L.NodeModel ()
acceptHello2 (HelloRequest2 msg) = error $ "Accepting HelloRequest2: " ++ show msg

bootNode :: (Member L.NodeDefinitionL effs) => Eff effs ()
bootNode = do
  _         <- L.nodeTag bootNodeTag
  _         <- L.initialization $ pure $ D.NodeID "abc"
  _         <- L.serving $ L.serve @HelloRequest1 acceptHello1
  pure ()

-- TODO: with NodeModel, evalNework not needed.
-- TODO: make TCP Sockets / WebSockets stuff more correct
masterNodeInitialization :: Eff L.NodeModel (Either Text D.NodeID)
masterNodeInitialization = do
  bootNodeAddr <- L.evalNetwork simpleBootNodeDiscovery
  eHashID      <- fmap unpack <$> L.withConnection (D.ConnectionConfig bootNodeAddr) GetHashIDRequest
  pure $ eHashID >>= Right . D.NodeID

-- TODO: handle the error correctly.
masterNode :: (Member L.NodeDefinitionL effs) => Eff effs ()
masterNode = do
  _         <- L.nodeTag masterNodeTag
  _         <- D.withSuccess $ L.initialization masterNodeInitialization
  _         <- L.serving
                  $ L.serve @HelloRequest1 acceptHello1
                  . L.serve @HelloRequest2 acceptHello2
  pure ()

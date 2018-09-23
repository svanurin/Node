
module Enecuum.Framework.NodeSpec where

import Enecuum.Prelude

import           Test.Hspec

import           Enecuum.Framework.Domain.Networking
import           Enecuum.Framework.TestData.RPC
import           Enecuum.Framework.TestData.Nodes
import           Enecuum.Framework.Testing.Runtime
import           Enecuum.Framework.Testing.Types
import qualified Enecuum.Core.Testing.Runtime.Lens as RLens
import qualified Enecuum.Framework.Testing.Lens as RLens
import           Enecuum.Framework.Domain.RpcMessages as R
import           Data.Aeson as A

spec :: Spec
spec = describe "Nodes test" $ do
  it "Master node interacts with boot node" $ do

    runtime <- createTestRuntime

    bootNodeRuntime   :: NodeRuntime <- startNode runtime bootNodeAddr    bootNode
    masterNodeRuntime :: NodeRuntime <- startNode runtime masterNode1Addr masterNode

    Right (RpcResponseResult eResponse _) <- sendRequest runtime bootNodeAddr $ makeRequest (HelloRequest1 (infoToText masterNode1Addr))

    A.fromJSON eResponse `shouldBe` (A.Success $ HelloResponse1 ("Hello, dear. " <> infoToText masterNode1Addr))

    let tMsgs = runtime ^. RLens.loggerRuntime . RLens.messages
    msgs <- readTVarIO tMsgs
    msgs `shouldBe`
      [ "Master node got id: NodeID \"1\"."
      ]

  it "Network node requests data from network node" $ do

    runtime <- createTestRuntime

    void $ startNode' runtime networkNode1Addr networkNode1
    void $ startNode runtime networkNode2Addr networkNode2

    let tMsgs = runtime ^. RLens.loggerRuntime . RLens.messages
    msgs <- readTVarIO tMsgs
    msgs `shouldBe`
      [ "balance4 (should be 111): 111."
      , "balance3 (should be Just 111): Just 111."
      , "balance2 (should be Nothing): Nothing."
      , "balance1 (should be Just 10): Just 10."
      , "balance0 (should be 0): 0."
      ]

  it "Boot node validates requests from Network node" $ do

    runtime <- createTestRuntime

    bootNodeValidationRuntime   :: NodeRuntime <- startNode runtime bootNodeAddr    bootNodeValidation
    masterNodeValidationRuntime :: NodeRuntime <- startNode runtime masterNode1Addr masterNodeValidation

    let tMsgs = runtime ^. RLens.loggerRuntime . RLens.messages
    msgs <- readTVarIO tMsgs
    msgs `shouldBe`
      [ "Master node got id: NodeID \"1\"."
      , "For the invalid request recieved ValidationResponse (Left [\"invalid\"])."
      , "For the valid request recieved ValidationResponse (Right \"correct\")."
      ]

  it "Network node uses state" $ do

    runtime <- createTestRuntime

    void $ startNode' runtime networkNode3Addr networkNode3
    void $ startNode runtime networkNode4Addr networkNode4

    let tMsgs = runtime ^. RLens.loggerRuntime . RLens.messages
    msgs <- readTVarIO tMsgs
    msgs `shouldBe`
      [ "balance (should be 91): 91."
      ]

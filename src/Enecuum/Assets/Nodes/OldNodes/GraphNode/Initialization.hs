module Enecuum.Assets.Nodes.OldNodes.GraphNode.Initialization where

import qualified Data.Aeson                                     as A
import qualified Data.Map                                       as Map
import qualified Enecuum.Assets.Nodes.Address                   as A
import qualified Enecuum.Assets.Nodes.GraphNode.Config          as Prd
import qualified Enecuum.Assets.Nodes.GraphNode.Database        as Prd
import           Enecuum.Assets.Nodes.GraphNode.Logic
import           Enecuum.Assets.Nodes.Methods
import qualified Enecuum.Assets.Nodes.OldNodes.GraphNode.CLens  as CLens
import           Enecuum.Assets.Nodes.OldNodes.GraphNode.Config
import           Enecuum.Config
import qualified Enecuum.Domain                                 as D
import qualified Enecuum.Language                               as L
import           Enecuum.Prelude
import qualified Enecuum.Language                 as L
import qualified Enecuum.Assets.System.Directory  as L
import qualified Enecuum.Blockchain.DB            as D
import           System.FilePath                  ((</>))

type OldGraphNodeData = GraphNodeData' OldGraphNode

initOldDBModel :: NodeConfig OldGraphNode -> L.NodeL (Maybe D.DBModel)
initOldDBModel nodeConfig = do

    parentDir <- if nodeConfig ^. CLens.useEnqHomeDir
        then L.getEnecuumDir
        else pure ""

    let dbModelPath = parentDir </> (nodeConfig ^. CLens.dbModelName)
    initDBModel' dbModelPath $ nodeConfig ^. CLens.dbOptions

-- | Initialization of graph node
graphNodeOldInitialization :: NodeConfig OldGraphNode -> L.NodeDefinitionL (Either Text OldGraphNodeData)
-- graphNodeOldInitialization nodeConfig = undefined
graphNodeOldInitialization nodeConfig = L.scenario $ do
    let useDb       = nodeConfig ^. CLens.useDatabase
    let stopOnDbErr = nodeConfig ^. CLens.stopOnDatabaseError

    mbDBModel <- if useDb
        then initOldDBModel nodeConfig
        else pure Nothing

    g <- L.newGraph
    L.evalGraphIO g $ L.newNode $ D.KBlockContent D.genesisKBlock

    nodeData <- L.atomically
        $  GraphNodeData' <$>
            ( D.BlockchainData g
                <$> L.newVar Map.empty
                <*> L.newVar Map.empty
                <*> L.newVar D.genesisHash
                <*> L.newVar Map.empty
            )
        <*> L.newVar L.NodeActing
        <*> pure nodeConfig
        <*> pure mbDBModel
        <*> L.newVar False
        <*> L.newVar False
        <*> L.newVar False

    let dbUsageFailed = useDb && stopOnDbErr && isNothing mbDBModel

    unless dbUsageFailed
        $ L.logInfo $ "Genesis block (" +|| D.genesisHash ||+ "): " +|| D.genesisKBlock ||+ "."

    if dbUsageFailed
        then pure $ Left "Database error."
        else pure $ Right nodeData
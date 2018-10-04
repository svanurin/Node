module App.Initialize where

import           Enecuum.Prelude

import           Enecuum.Config  (Config(..), ScenarioNode(..),NodeRole(..), Scenario(..), ScenarioRole(..))
import qualified Enecuum.Core.Lens as Lens
import qualified Enecuum.Assets.Scenarios as S
import           Enecuum.Assets.System.Directory (appFileName)
import           Enecuum.Interpreters (runNodeDefinitionL)
import           Enecuum.Runtime (NodeRuntime(..), createNodeRuntime, createLoggerRuntime,
                                  clearNodeRuntime, clearLoggerRuntime,
                                  createCoreRuntime, clearCoreRuntime)
import qualified Enecuum.Blockchain.Domain.Graph as TG
import qualified Enecuum.Framework.RLens as Lens
import qualified Enecuum.Language as L


    -- TODO: make this more correct.
    -- TODO: use bracket idiom here

initialize :: Config -> IO ()
initialize config = do
    putStrLn @Text "Getting log file..."
    let loggerConfig' = (loggerConfig config)
    let logFile = loggerConfig' ^. Lens.logFilePath
    putStrLn @Text $ "Log file: " +| logFile |+ "."

    putStrLn @Text "Creating logger runtime..."
    loggerRt <- createLoggerRuntime $ loggerConfig'
    putStrLn @Text "Creating core runtime..."
    coreRt <- createCoreRuntime loggerRt
    putStrLn @Text "Creating node runtime..."
    nodeRt <- createNodeRuntime coreRt
    forM_ (scenarioNode config) $ (\scenarioCase-> forkIO $ runNodeDefinitionL nodeRt $ do
        L.logInfo $ "Starting " +|| nodeRole scenarioCase ||+ " node..."
        L.logInfo $ "Starting " +|| scenario scenarioCase ||+ " scenario..."
        L.logInfo $ "Starting " +|| scenarioRole scenarioCase ||+ " role..."
        dispatchScenario config scenarioCase)
        -- TODO: this is a quick hack. Make it right.
    atomically $ readTMVar (nodeRt ^. Lens.stopNode)

    putStrLn @Text "Clearing node runtime..."
    clearNodeRuntime nodeRt
    putStrLn @Text "Clearing core runtime..."
    clearCoreRuntime coreRt
    putStrLn @Text "Clearing logger runtime..."
    clearLoggerRuntime loggerRt

dispatchScenario :: Config -> ScenarioNode -> L.NodeDefinitionL ()
dispatchScenario config (ScenarioNode BootNode _ _) = S.bootNode config
dispatchScenario config (ScenarioNode MasterNode _ _) = S.masterNode config
dispatchScenario _ (ScenarioNode NetworkNode Sync Respondent)  = S.networkNode3
dispatchScenario _ (ScenarioNode NetworkNode Sync Interviewer) = S.networkNode4
dispatchScenario _ (ScenarioNode PoW SyncKblock Soly) = S.powNode
dispatchScenario _ (ScenarioNode PoA SyncKblock Soly) = S.poaNode
dispatchScenario _ (ScenarioNode NetworkNode SyncKblock Soly) = S.nnNode
dispatchScenario _ (ScenarioNode role scenario scenarioRole) = error mes
  where m1 = "This scenario: " :: Text
        m2 = show @Text role
        m3 = show @Text scenario
        m4 = show @Text scenarioRole
        m5 = " doesn't exist" :: Text
        mes :: Text = mconcat $ m1 : m2 : m3 : m4 : m5 : []

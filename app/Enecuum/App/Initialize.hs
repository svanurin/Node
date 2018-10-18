module App.Initialize where

import           Enecuum.Prelude

import           Enecuum.Config  (Config(..), ScenarioNode(..), NodeRole(..), Scenario(..), ScenarioRole(..))
import qualified Enecuum.Core.Lens as Lens
import qualified Enecuum.Assets.Scenarios as S
import           Enecuum.Assets.System.Directory (appFileName)
import           Enecuum.Interpreters (runNodeDefinitionL, clearNodeRuntime)
import           Enecuum.Runtime (NodeRuntime(..), createNodeRuntime, createLoggerRuntime,
                                  clearLoggerRuntime,
                                  createCoreRuntime, clearCoreRuntime)
import qualified Enecuum.Language as L


    -- TODO: make this more correct.
    -- TODO: use bracket idiom here

initialize :: Config -> IO ()
initialize config = do
    putStrLn @Text "Getting log file..."
    let loggerConfig' = loggerConfig config
    let logFile       = loggerConfig' ^. Lens.logFilePath
    putStrLn @Text $ "Log file: " +| logFile |+ "."

    putStrLn @Text "Creating logger runtime..."
    loggerRt <- createLoggerRuntime loggerConfig'
    putStrLn @Text "Creating core runtime..."
    coreRt <- createCoreRuntime loggerRt
    putStrLn @Text "Creating node runtime..."
    nodeRt <- createNodeRuntime coreRt

    forM_ (scenarioNode config) $ \scenarioCase -> runNodeDefinitionL nodeRt $ do
        L.logInfo
            $   "Starting node.\n  Role: " +|| nodeRole scenarioCase
            ||+ "\n  Scenario: " +|| scenario scenarioCase
            ||+ "\n  Case: " +|| scenarioRole scenarioCase ||+ "..."
        dispatchScenario config scenarioCase

    putStrLn @Text "Clearing node runtime..."
    clearNodeRuntime nodeRt
    putStrLn @Text "Clearing core runtime..."
    clearCoreRuntime coreRt
    putStrLn @Text "Clearing logger runtime..."
    clearLoggerRuntime loggerRt

dispatchScenario :: Config -> ScenarioNode -> L.NodeDefinitionL ()
dispatchScenario config (ScenarioNode Client      _         _           ) = S.clientNode config
dispatchScenario _      (ScenarioNode PoW         Full      Soly        ) = S.powNode
dispatchScenario _      (ScenarioNode PoA         Full      Soly        ) = S.poaNode
dispatchScenario _      (ScenarioNode GraphNodeTransmitter   _         _           ) = S.graphNodeTransmitter
dispatchScenario _      (ScenarioNode GraphNodeReceiver   _         _           ) = S.graphNodeReceiver
dispatchScenario _      (ScenarioNode role        scenario  scenarioRole) = error mes
    where mes = "This scenario: " +|| role ||+ scenario ||+ scenarioRole ||+ " doesn't exist"

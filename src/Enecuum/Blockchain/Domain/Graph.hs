{-# LANGUAGE DeriveAnyClass #-}
-- TODO: this is copy-paste from tests with little changes.

module Enecuum.Blockchain.Domain.Graph where

import Enecuum.Prelude

import qualified Data.HGraph.THGraph     as G
import           Data.HGraph.StringHashable (StringHash, toHash)

import qualified Enecuum.Core.HGraph.Internal.Types as T
import qualified Enecuum.Language as L
import qualified Enecuum.Core.Types as D
import qualified Enecuum.Blockchain.Domain.Microblock as D
import qualified Enecuum.Blockchain.Domain.Transaction as D
import qualified Enecuum.Blockchain.Domain.KBlock as D
import           Enecuum.Core.HGraph.Interpreters.IO (runHGraphIO)
import           Enecuum.Core.HGraph.Internal.Impl (initHGraph)
import qualified Data.Serialize          as S
import qualified Data.ByteString.Base64  as Base64
import qualified Crypto.Hash.SHA256      as SHA
import           Data.HGraph.StringHashable (StringHash (..), StringHashable, toHash)

data NodeContent
  = KBlockContent D.KBlock
  | MBlockContent D.Microblock
  deriving (Show, Eq, Generic, ToJSON, FromJSON, Serialize)

instance StringHashable NodeContent where
  toHash (KBlockContent block)= toHash block
  toHash (MBlockContent block)= toHash block

type GraphVar  = D.TGraph NodeContent
type GraphL a  = L.HGraphL NodeContent a
type GraphNode = T.TNodeL NodeContent

genesisHash :: StringHash
genesisHash = toHash $ KBlockContent genesisKBlock

genesisKBlock :: D.KBlock
genesisKBlock = D.KBlock
    { D._prevHash   = toHash (0 :: Int)
    , D._number     = 0
    , D._nonce      = 0
    , D._solver     = toHash (0 :: Int)
    }

initGraph :: IO GraphVar
initGraph = do
    graph <- initHGraph
    runHGraphIO graph $ L.newNode $ KBlockContent genesisKBlock
    pure graph

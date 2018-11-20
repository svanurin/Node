{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Enecuum.Blockchain.DB.Entities.MBlock where

import qualified Data.Aeson                            as A
import qualified Data.ByteString.Lazy                  as LBS
import           Enecuum.Prelude
import           Text.Printf                           (printf)

import           Enecuum.Blockchain.DB.Entities.KBlock (toKBlockIdxBase)
import           Enecuum.Blockchain.DB.Entities.Types  (KBlockIdx, MBlockIdx)
import           Enecuum.Blockchain.DB.Model           (MBlocksDB)
import qualified Enecuum.Blockchain.Domain.KBlock      as D
import qualified Enecuum.Blockchain.Domain.Microblock  as D
import qualified Enecuum.Blockchain.Lens               as Lens
import qualified Enecuum.Core.Types                    as D


-- mBlocks (kBlock_idx|mBlock_idx -> mBlock_data)
-- --------------------------------------------------------------------
-- 0000001|001 {publisher: 3, signature: <signature>}
-- 0000001|002 {publisher: 5, signature: <signature>}
-- 0000002|001 {publisher: 1, signature: <signature>}

data MBlockEntity

instance D.DBModelEntity MBlocksDB MBlockEntity

instance D.DBEntity MBlockEntity where
    data DBKey MBlockEntity = MBlockKey (KBlockIdx, MBlockIdx)
        deriving (Show, Eq, Ord)

    data DBValue MBlockEntity = MBlockValue
            { publisher :: D.PublicKey  -- Temporarily not an index
            , signature :: D.Signature
            }
        deriving (Show, Eq, Ord, Generic, ToJSON, FromJSON)

instance D.ToDBKey MBlockEntity (KBlockIdx, MBlockIdx) where
    toDBKey = MBlockKey

instance D.ToDBValue MBlockEntity D.Microblock where
    toDBValue mBlock = MBlockValue (mBlock ^. Lens.publisher) (mBlock ^. Lens.signature)

instance D.RawDBEntity MBlocksDB MBlockEntity where
    toRawDBKey (MBlockKey (kBlockIdx, mBlockIdx)) = encodeUtf8 $ toKBlockIdxBase kBlockIdx <> toMBlockIdxBase mBlockIdx
    toRawDBValue = LBS.toStrict . A.encode
    fromRawDBValue = A.decode . LBS.fromStrict

toMBlockIdxBase :: MBlockIdx -> String
toMBlockIdxBase = printf "%03d"

{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE DuplicateRecordFields    #-}
{-# LANGUAGE FlexibleContexts         #-}
{-# LANGUAGE LambdaCase               #-}
{-# LANGUAGE NamedFieldPuns           #-}
{-# LANGUAGE OverloadedStrings        #-}
{-# LANGUAGE PackageImports           #-}
{-# LANGUAGE RecordWildCards          #-}
{-# LANGUAGE ScopedTypeVariables      #-}
{-# OPTIONS_GHC -fno-warn-orphans     #-}

module Service.Transaction.Decode where
import           Control.Concurrent.Chan.Unagi.Bounded
import           Control.Exception
import qualified Data.Serialize                        as S (decode, encode)
import           Service.InfoMsg                       (InfoMsg (..),
                                                        LogingTag (..),
                                                        MsgType (..))
-- import           Service.Transaction.Storage
import qualified Crypto.Hash.SHA256                    as SHA
import           Data.Aeson                            hiding (Error)
import           Data.Aeson.Types                      (parseMaybe)
import qualified Data.ByteString.Base64                as Base64
import qualified Data.ByteString.Char8                 as BC
import qualified Data.ByteString.Internal              as BSI
import           Data.Default                          (def)
import           Data.Pool
import qualified Data.Serialize                        as S (Serialize (..))
import qualified "rocksdb-haskell" Database.RocksDB    as Rocks
import           Node.Data.GlobalLoging
import           Service.Types
import           Service.Types.PublicPrivateKeyPair
import           Service.Types.SerializeJSON

-- for rocksdb Transaction and Microblock
rHashT :: Transaction -> BSI.ByteString
rHashT t@(Transaction {}) = Base64.encode . SHA.hash . S.encode $ t { _timestamp = Nothing }

rHash :: S.Serialize a => a -> BSI.ByteString
rHash key = Base64.encode . SHA.hash . S.encode $ key


lastKeyBlock :: DBKey
lastKeyBlock = "OvS8LmmcMa4mtEWbifO5ZFkqT6AYRizzQ6mEobMMhz4=" :: DBKey


funW ::  Pool Rocks.DB -> [(DBKey, DBValue)] -> IO ()
funW db aMapKeyValue = do
  let fun = (\aDb -> Rocks.write aDb def{Rocks.sync = True} (map (\(k,v) -> Rocks.Put k v) aMapKeyValue))
  withResource db fun


funR ::  Pool Rocks.DB -> DBKey -> IO (Maybe BSI.ByteString)
funR db key = do
  let fun = (\aDb -> Rocks.get aDb Rocks.defaultReadOptions key)
  withResource db fun


funD ::  Pool Rocks.DB -> DBKey -> IO ()
funD db key = do
  let fun = (\aDb -> Rocks.delete aDb def{Rocks.sync = True} key)
  withResource db fun


getByHash :: Pool Rocks.DB -> Hash -> IO (Maybe DBValue)
getByHash pool aHash = (\(Hash key) -> funR pool key) aHash



---- Decode
decodeThis :: S.Serialize p => BSI.ByteString -> p
decodeThis res = case (S.decode res) of
  Left e  -> throw $ DecodeException $ show e
  Right r -> r


decodeRaw :: S.Serialize a => Maybe DBValue -> Maybe a
decodeRaw this = case this of
  Nothing -> Nothing
  Just j  -> Just $ decodeThis j


-- MacroblockBD
getKeyBlockByHash :: DBPoolDescriptor -> InChan InfoMsg -> Hash  -> IO (Maybe MacroblockBD)
getKeyBlockByHash db _ kHash = decodeRaw <$> getByHash (poolMacroblock db) kHash


--Microblock
getMicroBlockByHashDB :: DBPoolDescriptor -> Hash -> IO MicroblockBD
getMicroBlockByHashDB db mHash = do
  res <- decodeRaw <$> getByHash (poolMicroblock db) mHash
  case res of
    Nothing -> throw (NoSuchMicroBlockForHash $ show mHash)
    Just j  -> return j


--Transaction
getTransactionByHashDB :: DBPoolDescriptor -> Hash -> IO (Maybe TransactionInfo)
getTransactionByHashDB db tHash = decodeRaw <$> getByHash (poolTransaction db) tHash


decodeTransactionAndFilterByKey :: PublicKey -> DBValue ->  Maybe TransactionAPI
decodeTransactionAndFilterByKey pubKey rawTx  = txAPI
  where txInfo = (decodeThis rawTx) :: TransactionInfo
        tx = _tx (txInfo :: TransactionInfo)
        -- condition t = _owner t == pubKey || _receiver t == pubKey
        txAPI = if (txFilterByKey pubKey tx)
          then Just $ TransactionAPI { _tx = tx, _txHash = rHashT tx}
          else Nothing


decodeAndFilter :: PublicKey -> DBValue -> Bool
decodeAndFilter pubKey rawTx  = isKeyThere
  where txInfo = (decodeThis rawTx) :: TransactionInfo
        tx = _tx (txInfo :: TransactionInfo)
        isKeyThere = txFilterByKey pubKey tx


txFilterByKey :: PublicKey -> Transaction -> Bool
txFilterByKey pubKey t = _owner t == pubKey || _receiver t == pubKey

-- Chain
getChain :: Common -> Number -> IO Chain
getChain (Common descr _ ) aNumber = do
  maybeV <- funR (poolSprout descr) (S.encode aNumber)
  case maybeV of
    Nothing -> return (Nothing, Nothing)
    Just m  -> return $ decodeThis m


--Ledger
getBalanceForKey :: DBPoolDescriptor -> PublicKey -> IO (Maybe Amount)
getBalanceForKey db key = decodeRaw <$> funR (poolLedger db) (S.encode key)


--Last Number
getLastKeyBlockNumber :: Common -> IO (Maybe Number)
getLastKeyBlockNumber (Common descr _) = decodeRaw <$> funR (poolLast descr) lastKeyBlock


--KeyBlock
decodeKeyBlock :: InChan InfoMsg -> Value -> IO KeyBlockInfoPoW
decodeKeyBlock i (Object aValue) = do
  let keyBlock = case parseMaybe (.: "verb") aValue of
        Nothing     -> throw (DecodeException "There is no verb in PoW Key Block")
        Just kBlock -> kBlock :: BC.ByteString --Map T.Text Value
  if keyBlock /= "kblock"
    then throw $ DecodeException $ "Expected kblock, but get: " ++ show keyBlock
    else do
    let body = case parseMaybe (.: "body") aValue of
          Nothing     -> throw (DecodeException "Can not parse body of PoW Key Block ")
          Just kBlock -> kBlock :: BC.ByteString --BSI.ByteString --KeyBlockInfo --Map T.Text Value

    case Base64.decode body of
      Left e -> throw (DecodeException (show e))
      Right r -> do
        case Data.Aeson.eitherDecodeStrict $ BC.init $ BC.tail r of
          Left a -> throw (DecodeException $ "There is no PoW Key Block. The error: " ++ a)
          Right (keyBlockInfo ) -> do
            -- let aKeyBlock = tKBIPoW2KBI keyBlockInfo
            --     aKeyBlockHash = getKeyBlockHash keyBlockInfo

            -- writeLog i [KeyBlockTag] Info $ "keyBlockHash: " ++ show aKeyBlockHash
            writeLog i [KeyBlockTag] Info $ "keyBlockInfo: " ++ show keyBlockInfo
            return keyBlockInfo
decodeKeyBlock _ v  = throw $ DecodeException $ "Can not decode PoW Key Block" ++ show v

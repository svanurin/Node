{-# LANGUAGE TemplateHaskell#-}

module Enecuum.TGraph where

import           Data.Map as M
import           Control.Monad
import           Control.Monad.STM
import           Control.Concurrent.STM.TVar
import           Lens.Micro
import           Lens.Micro.TH
import           Data.Maybe

type TGraph a b = Map a (TVar (TNode a b))

data TNode a b = TNode {
    _tNodeName  :: a,
    _graphIndex :: TVar (TGraph a b),
    _links      :: Map a (TVar (TNode a b)),
    _rLinks     :: [TVar (TNode a b)],
    _content    :: b
  }

makeLenses ''TNode

newIndex :: Ord a => STM (TVar (TGraph a b))
newIndex = newTVar mempty


newTNode :: Ord a => TVar (TGraph a b) -> a -> b -> STM ()
newTNode aIndex aName aContent = do
    aRes <- findNode aName aIndex
    when (isNothing aRes) $ do
        aTNode <- newTVar $ TNode aName aIndex mempty [] aContent
        modifyTVar aIndex $ insert aName aTNode



addTNode :: Ord a => TVar (TNode a b) -> a -> b -> STM ()
addTNode aTNode aLinck aContent = do
    aNode     <- readTVar aTNode
    aRes <- findNode aLinck (aNode ^. graphIndex)
    when (isNothing aRes) $ do
        aNewTNode <- newTVar $ TNode aLinck (aNode ^. graphIndex) mempty [] aContent
        modifyTVar (aNode ^. graphIndex) $ insert aLinck aTNode
        modifyTVar aTNode    (links %~ insert aLinck aNewTNode)
        modifyTVar aNewTNode (rLinks %~ (aTNode :))


addLinck :: Ord a => TVar (TNode a b) -> TVar (TNode a b) -> STM ()
addLinck aTNode1 aTNode2 = do
    aNode2 <- readTVar aTNode2
    modifyTVar aTNode1 $ links %~ insert (aNode2 ^. tNodeName) aTNode2
    modifyTVar aTNode2 (rLinks %~ (aTNode1 :))


deleteLinck :: Ord a => a -> TVar (TNode a b) -> STM ()
deleteLinck aLinck aTNode = modifyTVar aTNode (links %~ delete aLinck)


deleteNode :: Ord a => TVar (TNode a b) -> STM ()
deleteNode aTNode = do
    aNode <- readTVar aTNode
    modifyTVar (aNode ^. graphIndex) $ delete (aNode ^. tNodeName)
    forM_ (aNode ^. rLinks)
        $ \aVar -> modifyTVar aVar (links %~ delete (aNode ^. tNodeName))


findNode :: Ord a => a -> TVar (TGraph a b) -> STM (Maybe (TVar (TNode a b)))
findNode aName aTIndex = M.lookup aName <$> readTVar aTIndex
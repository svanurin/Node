{-# LANGUAGE ViewPatterns #-}
module Sharding.Space.Shift where

import              Sharding.Space.Point
import              Sharding.Space.Distance

import              Data.List.Extra
import              Data.Word
import qualified    Data.Set            as S


checkUnevenness :: MyNodePosition -> S.Set NodePosition -> Bool
checkUnevenness aMyNodePosition aPositions =
  -- TODO CHECK (length aDistances == 4)
    (length aDistances == 4) && (minimum aDistances `div` 4 < maximum aDistances `div` 5)
  where
    aDistances = distanceTo aMyNodePosition <$>
        findNearestNeighborPositions aMyNodePosition aPositions


findNearestNeighborPositions :: MyNodePosition -> S.Set NodePosition -> [NodePosition]
findNearestNeighborPositions
    (MyNodePosition aMyNodePosition) (S.toList -> aPositions) = aElect <$> [
        distanceEast, distanceWest, distanceSout, distanceNorth]
  where
    aElect :: (Point -> Point -> Word64) -> NodePosition
    aElect aDistance = minimumOn
        (\(NodePosition aPoint) -> aDistance aMyNodePosition aPoint) aPositions

shiftToCenterOfMass :: MyNodePosition -> S.Set NodePosition -> MyNodePosition
shiftToCenterOfMass aMyNodePosition aNearestPositions
      | S.size aNearestPositions == 1 = moveToOneSixteenth aMyNodePosition (head $ S.toList aNearestPositions)
      | S.size aNearestPositions >= 2 = moveToTriangle aMyNodePosition $ take 2 $ sortOn (distanceTo aMyNodePosition) $ S.toList aNearestPositions
shiftToCenterOfMass aMyNodePosition _ = aMyNodePosition

moveToOneSixteenth :: MyNodePosition -> NodePosition -> MyNodePosition
moveToOneSixteenth (MyNodePosition (Point x1 y1)) (NodePosition (Point x2 y2))
      | x1 <= x2 && y1 <= y2 = MyNodePosition $ Point (x1 `minusInWorld` oneSixteenth) (y1 `minusInWorld` oneSixteenth)
      | x1 > x2 && y1 <= y2  = MyNodePosition $ Point (x1 `plusInWorld` oneSixteenth) (y1 `minusInWorld` oneSixteenth)
      | x1 <= x2 && y1 > y2  = MyNodePosition $ Point (x1 `minusInWorld` oneSixteenth) (y1 `plusInWorld` oneSixteenth)
      | otherwise            = MyNodePosition $ Point (x1 `plusInWorld` oneSixteenth) (y1 `plusInWorld` oneSixteenth)

moveToTriangle :: MyNodePosition -> [NodePosition] -> MyNodePosition
moveToTriangle aMyNodePosition [NodePosition p1, NodePosition p2]
    | distanceTo (NodePosition p1) (NodePosition p2) < distanceTo aMyNodePosition (NodePosition p1) || distanceTo (NodePosition p1) (NodePosition p2) < distanceTo aMyNodePosition (NodePosition p2)
        = aMyNodePosition
    | distanceTo aMyNodePosition (NodePosition point1) > distanceTo aMyNodePosition (NodePosition point2)
        = MyNodePosition point2
    | otherwise = MyNodePosition point1
        where
          (point1, point2) = countPointInWorld p1 p2
moveToTriangle a _ = a


countPointInWorld :: Point -> Point-> (Point, Point)
countPointInWorld (Point x1 y1) (Point x2 y2) = (Point (fromInteger xm1) (fromInteger ym1) , Point (fromInteger xm2) (fromInteger ym2) )
    where
      mx = toInteger x2 - toInteger x1
      my = toInteger y2 - toInteger y1
      xm1 = div mx 2 - div (my*866) 1000 + toInteger x1
      xm2 = div mx 2 + div (my*866) 1000 + toInteger x1
      ym1 = div my 2 + div (mx*866) 1000 + toInteger y1
      ym2 = div my 2 - div (mx*866) 1000 + toInteger y1

oneSixteenth :: Word64
oneSixteenth = maxBound `div` 32

findSupportNeighborPosition ::
        MyNodePosition
    ->  S.Set NodePosition
    ->  NodePosition
    -> (Point -> Point -> Word64)
    ->  NodePosition
findSupportNeighborPosition aMyNodePosition aNearestPositions aSupportPoint aDist =
    head $ sortOn aDistanceToMe $
    filter aIsInSupportFourthOfSpace $ S.elems aNearestPositions
  where
    aIsInSupportFourthOfSpace :: NodePosition -> Bool
    aIsInSupportFourthOfSpace aNodePosition =
        distanceTo aSupportPoint aNodePosition < maxBound `div` 2

    aDistanceToMe :: NodePosition -> Distance Point
    aDistanceToMe (NodePosition aNeighborPosition) =
        aDist aMyNodePositionPoint aNeighborPosition

    MyNodePosition aMyNodePositionPoint = aMyNodePosition
--

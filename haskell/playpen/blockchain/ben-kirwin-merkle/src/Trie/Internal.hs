{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Trie.Internal
  ( NodeDB, Digest(..)
  , getNode, putNode
  , lookupPath
  , insertRef, insertPath
  , emptyRef, normalize
  , Ref(..), Node(..)
  )
where

import           PPrelude
import qualified RLP                 as RLP
import           Trie.Path

import           Control.Monad.State
import qualified Crypto.Hash.SHA3    as SHA3
import qualified Data.ByteString     as BS
import           Data.Char           (intToDigit)
import           Data.Foldable       (toList)
import           Data.List           (stripPrefix)
import           Data.Sequence       (Seq)
import qualified Data.Sequence       as Seq

newtype Digest = Digest ByteString
  deriving (Ord, Eq, RLP.Convertible)

instance Show Digest where
  show (Digest bs) = map (intToDigit . word4toInt) $ unpackWord4s bs

data Ref = Hash Digest | Literal Node
  deriving (Show, Eq)

data Node = Empty
          | Shortcut Path (Either Ref ByteString)
          | Full (Seq Ref) ByteString
  deriving (Show, Eq)

instance RLP.Convertible Ref where
  converter = RLP.Converter to from
    where
      to (Hash h)    = RLP.toItem h
      to (Literal l) = RLP.toItem l
      from rlp = do
        bytes <- RLP.fromItem rlp
        if BS.length bytes < 32
          then RLP.decode bytes >>= RLP.fromItem
          else return . Hash . Digest $ bytes

instance RLP.Convertible Node where
  converter = RLP.Converter to from
    where
      to Empty = RLP.toItem BS.empty
      to (Shortcut path (Right val)) = RLP.toItem [encodePath True path, val]
      to (Shortcut path (Left ref)) = RLP.toItem [RLP.toItem $ encodePath False path, RLP.toItem ref]
      to (Full refs val) = RLP.toItem (fmap RLP.toItem refs <> Seq.singleton (RLP.toItem val))
      from (RLP.String bs)
        | BS.null bs = Just Empty
        | otherwise = Nothing
      from (RLP.List [pathItem, targetItem]) = do
        pathBS <- RLP.fromItem pathItem
        (isTerminal, path) <- decodePath pathBS
        target <-
          if isTerminal then Right <$> RLP.fromItem targetItem
          else Left <$> RLP.fromItem targetItem
        return $ Shortcut path target
      from (RLP.List many) = do
        guard $ length many == 17
        refs <- mapM RLP.fromItem $ init many
        val <- RLP.fromItem $ last many
        return $ Full (Seq.fromList refs) val

type NodeDB = DB Digest Node

putNode :: Node -> NodeDB Ref
putNode node =
  let bytes = RLP.encode $ RLP.toItem node
      digest = Digest $ SHA3.hash 256 bytes
  in if BS.length bytes < 32
    then return $ Literal node
    else do
      insertDB digest node
      return $ Hash digest

getNode :: Ref -> NodeDB Node
getNode (Hash d)    = lookupDB d
getNode (Literal n) = return n

lookupPath :: Ref -> Path -> NodeDB ByteString
lookupPath root path = getNode root >>= getVal
  where
    getVal Empty = return BS.empty
    getVal (Shortcut nodePath result) =
      case (stripPrefix nodePath path, result) of
        (Just [], Right value)     -> return value
        (Just remaining, Left ref) -> lookupPath ref remaining
        _                          -> return BS.empty
    getVal (Full refs val) = case path of
      []       -> return val
      (w:rest) -> lookupPath (refs `Seq.index` word4toInt w) rest

emptyRefs = Seq.replicate 16 $ Literal Empty
emptyRef = Literal Empty

toFull :: Node -> NodeDB Node
toFull Empty = return $ Full emptyRefs BS.empty
toFull f@(Full _ _) = return f
toFull (Shortcut [] (Left ref)) = getNode ref >>= toFull
toFull (Shortcut [] (Right bs)) = return $ Full emptyRefs bs
toFull (Shortcut (p:ps) val) = do
  ref <- putNode $ Shortcut ps val
  let newRefs = Seq.update (word4toInt p) ref emptyRefs
  return $ Full newRefs BS.empty

insertPath :: Node -> Path -> ByteString -> NodeDB Node
insertPath node path bs = doInsert node >>= normalize
  where
    doInsert Empty = return $ Shortcut path $ Right bs
    doInsert (Shortcut nPath nVal) = do
      let (prefix, nSuffix, suffix) = splitPrefix nPath path
      next <- case (nSuffix, suffix, nVal) of
        ([], [], Right _) -> return $ Right bs
        ([], _, Left ref) -> do
          node <- getNode ref
          newNode <- insertPath node suffix bs
          return $ Left newNode
        _ -> do
          full <- toFull (Shortcut nSuffix nVal)
          newNode <- insertPath full suffix bs
          return $ Left newNode
      case (prefix, next) of
        ([], Left newNode) -> return newNode
        (_, Left newNode)  -> Shortcut prefix . Left <$> putNode newNode
        (_, Right bs)      -> return $ Shortcut prefix $ Right bs
    doInsert (Full refs val) = case path of
      [] -> return $ Full refs bs
      (p:ps) -> do
        let index = word4toInt p
            ref = refs `Seq.index` index
        newRef <- insertRef ref ps bs
        let newRefs = Seq.update index newRef refs
        return $ Full newRefs val

    splitPrefix [] b = ([], [], b)
    splitPrefix a [] = ([], a, [])
    splitPrefix (a:as) (b:bs)
      | a == b =
        let (prefix, aSuffix, bSuffix) = splitPrefix as bs
        in (a:prefix, aSuffix, bSuffix)
      | otherwise = ([], a:as, b:bs)

insertRef :: Ref -> Path -> ByteString -> NodeDB Ref
insertRef ref path bs = do
  node <- getNode ref
  newNode <- insertPath node path bs
  putNode newNode

normalize :: Node -> NodeDB Node
normalize Empty = return Empty
normalize (Shortcut path (Left ref)) = do
  node <- getNode ref
  addPrefix path node
normalize (Shortcut _ (Right val)) | BS.null val = return Empty
normalize s@(Shortcut _ _) = return s
normalize (Full refs val) = do
  let nrmlRefs = toList refs
      nonEmpty = filter (\x -> snd x /= Literal Empty) $ zip [0..] nrmlRefs
  case (BS.null val, nonEmpty) of
    (True, [])            -> return Empty
    (True, (w, ref) : []) -> getNode ref >>= addPrefix [sndWord4 w]
    (False, [])           -> return $ Shortcut [] $ Right val
    _                     -> return $ Full (Seq.fromList nrmlRefs) val

addPrefix [] node = return node
addPrefix path node = case node of
  Empty                -> return Empty
  Shortcut subpath val -> return $ Shortcut (path ++ subpath) val
  _                    -> Shortcut path . Left <$> putNode node

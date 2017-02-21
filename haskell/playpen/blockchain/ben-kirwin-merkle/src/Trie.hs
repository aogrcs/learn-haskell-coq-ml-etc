{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Trie
  (Trie, Digest, runTrie)
where

import           PPrelude
import           TrieInternal        as TI

import           Control.Monad.State
import           Prelude             hiding (lookup)

insert :: Ref -> ByteString -> ByteString -> NodeDB Ref
insert ref key val = insertRef ref (unpackWord4s key) val

lookup :: Ref -> ByteString -> NodeDB ByteString
lookup ref bs = lookupPath ref $ unpackWord4s bs

type Trie = StateT Ref NodeDB

runTrie :: DB ByteString ByteString a -> Trie a
runTrie = runDB putDB getDB
  where
    putDB key val = do
      ref <- get
      newRef <- lift $ insert ref key val
      put newRef
    getDB key = do
      ref <- get
      lift $ lookup ref key



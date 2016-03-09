{-# OPTIONS_GHC -fno-warn-missing-signatures -fno-warn-unused-binds #-}
{-# LANGUAGE OverloadedStrings #-}

module EntityTagCache where

import           Control.Monad   (liftM, (>=>))
import           Data.List       (isPrefixOf)
import           Data.Map.Strict as M
import           Data.Maybe      as MB (mapMaybe)
import           Prelude         as P
import           System.IO       (IOMode (ReadMode), hGetContents, withFile)
import           Test.HUnit      (Counts, Test (TestList), runTestTT)
import qualified Test.HUnit.Util as U (t)

------------------------------------------------------------------------------

type MSI   = Map String Int
type MIS   = Map Int    String

data Cache' a = Cache' !a
                       !Int -- next tag number
                       !MSI -- tag to tag number
                       !MIS -- tag number to tag
mii  (Cache' r _ _ _) = r
ss                    = mii
ks                    = mii
next (Cache' _ r _ _) = r
msi  (Cache' _ _ r _) = r
mis  (Cache' _ _ _ r) = r
type Cache            = Cache' (Map Int [Int]) -- entity id to tag numbers
type DDIn             = Cache' [String]        -- input  to DD
type DDOut            = Cache' [Int]           -- output of DD

------------------------------------------------------------------------------
-- Use cache

-- impure

getTagsIO             :: Int -> IO Cache -> IO (Maybe [String])
getTagsIO              = liftM . getTags

updateTagsIO          :: Int -> [String] -> IO Cache -> IO Cache
updateTagsIO x ts      = liftM (updateTags x ts)

-- pure

getTags               :: Int ->    Cache ->     Maybe [String]
getTags x c = M.lookup x (mii c) >>= \r -> return $ MB.mapMaybe (`M.lookup` mis c) r

updateTags            :: Int -> [String] ->    Cache ->    Cache
updateTags x ts c = -- (c,i0,msi0,mis0)
    let o = dedupTagIdTags (Cache' ts (next c) (msi c) (mis c))
    in Cache' (M.insert x (ks o) (mii c)) (next o) (msi o) (mis o)

------------------------------------------------------------------------------
-- Populate cache

loadCacheFromFile :: FilePath -> IO Cache
loadCacheFromFile filename =
    withFile filename ReadMode (hGetContents >=> return . stringToCache)

stringToCache     :: String -> Cache
stringToCache      = dedupTags . collectTagIdAndTags

------------------------------------------------------------------------------
-- Internals

collectTagIdAndTags :: String -> [(Int, [String])]
collectTagIdAndTags  = P.map mkEntry . lines
  where
    mkEntry x = let (i:xs) = splitOn "," x in (read i, xs)

dedupTags :: [(Int, [String])] -> Cache
dedupTags  = P.foldr level1 (Cache' M.empty (-1) M.empty M.empty)
  where
    level1 (tag, ss0) c =
        let o = dedupTagIdTags (Cache' ss0 (next c) (msi c) (mis c))
        in  Cache' (M.insert tag (ks o) (mii c)) (next o) (msi o) (mis o)

dedupTagIdTags :: DDIn -> DDOut
dedupTagIdTags i = P.foldr level2 (Cache' mempty (next i) (msi i) (mis i)) (ss i)
  where
    level2 s o = case M.lookup s (msi o) of
        Just j  ->
            Cache'      (j:ks o) (next o)                          (msi o)                       (mis o)
        Nothing ->
            Cache' (next o:ks o) (next o + 1) (M.insert s (next o) (msi o)) (M.insert (next o) s (mis o))

------------------------------------------------------------------------------
-- Test

exCsv = "0,foo,bar\n1,abc,foo\n2\n3,xyz,bar"
cToList c = (M.toList (mii c), next c, M.toList (msi c), M.toList (mis c))

tgt = U.t "tgt"
    (P.map (\i -> getTags i (stringToCache exCsv)) [0..4])
    [ Just ["foo","bar"]
    , Just ["abc","foo"]
    , Just []
    , Just ["xyz","bar"]
    , Nothing
    ]

tut = U.t "tut"
    (cToList $ updateTags 2 ["new1","new2"] (stringToCache exCsv))
    ( [(0,[1,-1]), (1,[2,1]), (2,[4,3]), (3,[0,-1])]
    , 5
    , [("abc",2),("bar",-1),("foo",1),("new1",4),("new2",3),("xyz",0)]
    , [(-1,"bar"),(0,"xyz"),(1,"foo"),(2,"abc"),(3,"new2"),(4,"new1")] )

tstc = U.t "tstc"
    (cToList $ stringToCache exCsv)
    ( [(0,[1,-1]), (1,[2,1]), (2,[]), (3,[0,-1])]
    , 3
    , [("abc",2),("bar",-1),("foo",1),("xyz",0)]
    , [(-1,"bar"),(0,"xyz"),(1,"foo"),(2,"abc")] )

tct = U.t "tct"
    (collectTagIdAndTags exCsv)
    [(0,["foo","bar"]), (1,["abc","foo"]), (2,[]), (3,["xyz","bar"])]

tddt = U.t "tddt"
    (let o = dedupTagIdTags (Cache' ["foo", "bar", "baz", "foo", "baz", "baz", "foo", "qux", "new"]
                                    (-1) M.empty M.empty)
     in  (ks o, next o, M.toList (msi o), M.toList (mis o)))
    (                               [    1,     3,     2,     1,     2,     2,     1,     0,    -1]
    , 4::Int
    , [("bar",3),("baz",2),("foo",1),("new",-1),("qux",0)]
    , [(-1,"new"),(0,"qux"),(1,"foo"),(2,"baz"),(3,"bar")])

test :: IO Counts
test =
    runTestTT $ TestList $ tgt ++ tut ++ tstc ++ tct ++ tddt

------------------------------------------------------------------------------
-- Utililties (I can't find this in the Haskell libraries available on stackage)

splitOn :: Eq a => [a] -> [a] -> [[a]]
splitOn _ [] = []
splitOn delim str =
    let (firstline, remainder) = breakList (isPrefixOf delim) str
    in firstline : case remainder of
        [] -> []
        x -> if x == delim
             then [[]]
             else splitOn delim (drop (length delim) x)

breakList :: ([a] -> Bool) -> [a] -> ([a], [a])
breakList func = spanList (not . func)

spanList :: ([a] -> Bool) -> [a] -> ([a], [a])
spanList _ [] = ([],[])
spanList func list@(x:xs) = if func list then (x:ys,zs) else ([],list)
  where (ys,zs) = spanList func xs

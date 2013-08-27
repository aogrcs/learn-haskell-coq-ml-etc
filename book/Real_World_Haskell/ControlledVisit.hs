module ControlledVisit where

-- "fix" imports
import Control.Monad (filterM, forM, liftM)
import System.Directory (doesDirectoryExist, getDirectoryContents, Permissions(..), getModificationTime, getPermissions)
import System.Time (ClockTime(..))
import System.FilePath (takeExtension, (</>))
import Control.Exception (bracket, handle, SomeException)
import System.IO (IOMode(..), hClose, hFileSize, openFile)

-- Similar to "InfoP a" in previous versions.
-- Use "record" syntax.
data Info = Info {
      infoPath    :: FilePath
    , infoPerms   :: Maybe Permissions
    , infoSize    :: Maybe Integer
    , infoModTime :: Maybe ClockTime
    } deriving (Eq, Ord, Show)

-- Limitation: avoids recursing into directories,
--             but can’t filter other names until after generating entire list of names in a tree.

-- Control which directories are entered and when.
-- Given a function that takes a list of Info representing subdirs.
--       Returns list with elements, removed and/or ordered differently.
traverse :: ([Info] -> [Info]) -> FilePath -> IO [Info]
traverse order path = do
    -- get contents at this level (skipping . and ..)
    names <- getUsefulContents path
    -- prepend the path to all contents, and add the path as well
    -- get information on each item
    contents <- mapM getInfo (path : map (path </>) names)
    -- "order" the contents (see above) then either drop into subdirs or return info on files
    -- liftM concat to work in IO monad: takes result of forM (type IO [[Info]]) out of IO monad,
    -- applies concat to it (type [Info]), puts result back into IO monad.
    liftM concat $ forM (order contents) $ \info -> do
        if isDirectory info && infoPath info /= path
            then traverse order (infoPath info)
            else return [info]

-- same as traverse above but more verbose
traverseVerbose order path = do
    names <- getDirectoryContents path
    let usefulNames = filter (`notElem` [".", ".."]) names
    contents <- mapM getEntryName ("" : usefulNames)
    recursiveContents <- mapM recurse (order contents)
    return (concat recursiveContents)
  where getEntryName name = getInfo (path </> name)
        isDirectory info = case infoPerms info of
                               Nothing    -> False
                               Just perms -> searchable perms
        recurse info = do
            if isDirectory info && infoPath info /= path
                then traverseVerbose order (infoPath info)
                else return [info]

getUsefulContents :: FilePath -> IO [String]
getUsefulContents path = do
    names <- getDirectoryContents path
    return (filter (`notElem` [".", ".."]) names)

getInfo :: FilePath -> IO Info
getInfo path = do
    perms    <- maybeIO (getPermissions path)
    size     <- maybeIO (bracket (openFile path ReadMode) hClose hFileSize)
    modified <- maybeIO (getModificationTime path)
    return (Info path perms size modified)

-- Turns IO action that might throw an exception into one that wraps its result in Maybe.
maybeIO :: IO a -> IO (Maybe a)
{- book version out-of-date with Haskell
maybeIO act = handle (\_ -> return Nothing) (Just `liftM` act)
-}
maybeIO act = handle handler (Just `liftM` act)
  where
    handler :: SomeException -> IO (Maybe a)
    handler _ = return Nothing

-- Gets the permissions of the given Info and asks if it is searchable.
-- searchable is a record field/accessor in Permissions
-- infoPerms returns Maybe Permissions
isDirectory :: Info -> Bool
isDirectory = maybe False searchable . infoPerms

{-
:m Data.Maybe
maybe :: b -> (a -> b) -> Maybe a -> b
maybe : if given Nothing then return its First arg (default value)
      : otherwise pass value inside Just to function and return function's value
maybe False id (Just False)
maybe False id (Just True)
maybe True id (Just False)
maybe True id (Just True)
maybe False id Nothing
maybe True  id Nothing
-}

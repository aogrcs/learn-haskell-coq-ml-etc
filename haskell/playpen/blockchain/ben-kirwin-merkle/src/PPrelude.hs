{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module PPrelude
  ( Word4, word4to8, packWord8, fstWord4, sndWord4, word4toInt, unpackWord4s
  , ByteString, Word8, Map
  , DB, insertDB, lookupDB, runDB
  , encodeInt, decodeInt
  , module X
  )
where

import           Control.Applicative as X
import           Control.Monad.Free
import           Data.Bits
import           Data.ByteString     (ByteString)
import qualified Data.ByteString     as BS
import           Data.Char           (intToDigit)
import           Data.Functor        as X
import           Data.Map            (Map)
import           Data.Maybe          as X
import           Data.Monoid         as X
import           Data.Word           (Word8)

encodeInt :: Integral n => n -> ByteString
encodeInt = BS.reverse <$> BS.unfoldr nextByte
  where
    nextByte 0 = Nothing
    nextByte n = Just (fromIntegral n, n `quot` 256)

decodeInt :: Integral n => ByteString -> Maybe n
decodeInt bs
  | not (BS.null bs) && BS.head bs == 0 = Nothing
  | otherwise = Just $ BS.foldl addByte 0 bs
  where
    addByte n b = (n * 256) + fromIntegral b

newtype Word4 = Word4 { word4to8 :: Word8 }
  deriving (Eq)

instance Show Word4 where
  show = (:[]) . intToDigit . word4toInt

packWord8 :: Word4 -> Word4 -> Word8
packWord8 (Word4 a) (Word4 b) = (a `shift` 4) .|. b

fstWord4, sndWord4 :: Word8 -> Word4
fstWord4 b = Word4 $ b `shiftR` 4
sndWord4 b = Word4 $ b .&. 0x0f

word4toInt :: Word4 -> Int
word4toInt = fromIntegral . word4to8

unpackWord4s :: ByteString -> [Word4]
unpackWord4s bs = BS.unpack bs >>= unpackByte
  where unpackByte b = [fstWord4 b, sndWord4 b]

data KV k v a
  = Put k v a
  | Get k (v -> a)
  deriving (Functor)

newtype DB k v a = DB (Free (KV k v) a)
  deriving (Functor, Applicative, Monad)

insertDB :: k -> v -> DB k v ()
insertDB k v = DB $ liftF $ Put k v ()

lookupDB :: k -> DB k v v
lookupDB k = DB $ liftF $ Get k id

-- Collapses a series of puts and gets down to the monad of your choice
runDB :: Monad m
      => (k -> v -> m ()) -- ^ The 'put' function for our desired monad
      -> (k -> m v)       -- ^ The 'get' function for the same monad
      -> DB k v a         -- ^ The puts and gets to execute
      -> m a
runDB put get (DB ops) = go ops
  where
    go (Pure a)               = return a
    go (Free (Put k v next))  = put k v >> go next
    go (Free (Get k handler)) = get k >>= go . handler

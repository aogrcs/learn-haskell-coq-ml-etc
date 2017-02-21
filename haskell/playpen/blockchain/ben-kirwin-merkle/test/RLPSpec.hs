{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module RLPSpec
  (spec, One(..), Other(..), Union(..))
where

import           PPrelude
import           RLP                 (asProduct, asUnderlying, tagged)
import qualified RLP                 as RLP

import           Testing

import           Control.Applicative
import qualified Data.Aeson          as A
import qualified Data.ByteString     as BS
import qualified Data.Text           as T
import           Data.Text.Encoding  (encodeUtf8)
import           GHC.Generics

import           Data.String         (IsString, fromString)

import           Test.Hspec
import           Test.QuickCheck

instance IsString RLP.Item where
  fromString = RLP.String . fromString

instance Arbitrary RLP.Item where
  arbitrary = sized item
    where
      item n
        | n <= 2 = strGen
        | otherwise = oneof [strGen, resize (n `div` 2) listGen ]
      strGen = RLP.String <$> arbitrary
      listGen = RLP.List <$> arbitrary

  shrink (RLP.String bytes) =
    RLP.String <$> shrink bytes
  shrink (RLP.List list) =
    let shrunkLists = RLP.List <$> shrink list
    in list ++ shrunkLists

instance A.FromJSON RLP.Item where
  parseJSON (A.Array a) = RLP.List <$> A.parseJSON (A.Array a)
  parseJSON (A.String s) =
    if not (T.null s) && T.head s == '#'
    then return . RLP.String . encodeInt . read . T.unpack . T.tail $ s
    else return . RLP.String . encodeUtf8 $ s
  parseJSON (A.Number n) =
    let decodeNum :: Integer -> RLP.Item
        decodeNum = RLP.String . encodeInt
    in decodeNum <$> A.parseJSON (A.Number n)

data RLPCase = RLPCase RLP.Item ByteString

instance A.FromJSON RLPCase where
  parseJSON (A.Object o) = RLPCase <$> o A..: "in"
                                   <*> o A..: "out"

data Empty = Empty
  deriving (Generic, Eq, Show)
data Single = Single ByteString
  deriving (Generic, Eq, Show)
data Many = Many ByteString ByteString
  deriving (Generic, Eq, Show)

data One = One
  deriving (Generic, Eq, Show)
data Other = Other Many
  deriving (Generic, Eq, Show)
data Union = OneU One
           | OtherU Other
  deriving (Generic, Eq, Show)

data Breaky = ShortB ByteString | LongB ByteString ByteString deriving (Show, Eq, Generic)

instance RLP.Convertible Empty
instance RLP.Convertible Single
instance RLP.Convertible Many
instance RLP.Convertible One where converter = tagged 0 asProduct
instance RLP.Convertible Other where converter = tagged 1 asProduct
instance RLP.Convertible Union where converter = asUnderlying
instance RLP.Convertible Breaky

spec :: Spec
spec = do
  it "should decode what it encodes" $ property $ \rlp ->
    (RLP.decode . RLP.encode $ rlp) `shouldBe` Just rlp

  it "should encode small bytes as themselves" $ property $ \byte ->
    byte < 0x80 ==>
      let oneByte = BS.pack [byte]
      in RLP.encode (RLP.String oneByte) `shouldBe` oneByte

  it "fails to decode truncated values" $ property $ \rlp n ->
    let serialized = RLP.encode rlp
        len = BS.length serialized
    in n >= 0 && n < len && len > 0 ==>
        RLP.decode (BS.take n serialized) `shouldBe` Nothing

  it "fails to decode padded values" $ property $ \rlp padding ->
    BS.length padding > 0 ==>
      RLP.decode (RLP.encode rlp <> padding) `shouldBe` Nothing

  describe "handles example conversions" $ do

    "dog" `encodesTo` "\x83\&dog"

    RLP.List ["cat", "dog"] `encodesTo` "\xc8\x83\&cat\x83\&dog"

    "" `encodesTo` "\x80"

    RLP.List [] `encodesTo` "\xc0"

    "\x0f" {-15-} `encodesTo` "\x0f"

    "\x04\x00" {-1024-} `encodesTo` "\x82\x04\x00"

    -- [ [], [[]], [ [], [[]] ] ]
    RLP.List [ RLP.List []
             , RLP.List [ RLP.List []]
             , RLP.List [ RLP.List []
                        , RLP.List [RLP.List []]
                        ]
             ]
      `encodesTo`
      "\xc7\xc0\xc1\xc0\xc3\xc0\xc1\xc0"

    it "should encode lorem ipsum properly" $
      let encoded = RLP.encode "Lorem ipsum dolor sit amet, consectetur adipisicing elit"
      in ( "\xb8\x38Lorem " `BS.isPrefixOf` encoded) && ("elit" `BS.isSuffixOf` encoded )

  describe "handles all common test cases" $ testCommon "rlptest" $ \test ->
    let RLPCase i o = test
    in i `encodesTo` o

  describe "derives reasonable encoding / decodings" $ do

    it "encodes an empty constructor as the empty list" $
      Empty `convertsTo` RLP.List []

    it "encodes a single-element constructor as a singleton list" $ property $ \bs ->
      Single bs `convertsTo` RLP.toItem [bs]

    it "encodes a product as a list" $ property $ \bs0 bs1 ->
      Many bs0 bs1 `convertsTo` RLP.toItem [bs0, bs1]

    it "implements tags" $ One `convertsTo` RLP.toItem [0 :: Int]

    it "encodes first element of a union" $
      OneU One `convertsTo` RLP.toItem One

    it "encodes the second element of a union" $ property $ \bs0 bs1 ->
      let other = Other $ Many bs0 bs1
      in OtherU other `convertsTo` RLP.toItem other

    it "should fail to decode a product when truncated" $ property $ \bs ->
      let tooShort = RLP.toItem [bs :: ByteString]
      in (RLP.fromItem tooShort :: Maybe Many) `shouldBe` Nothing

    it "should decode the correct data for a sum-of-products" $ property $ \bs0 bs1 ->
      LongB bs0 bs1 `convertsTo` RLP.toItem [bs0, bs1]

  where
    input `convertsTo` output = do
      RLP.toItem input `shouldBe` output
      RLP.fromItem output `shouldBe` Just input
    input `encodesTo` output = do
      it ("should encode " <> show input <> " as " <> show output) $
        RLP.encode input `shouldBe` output
      it ("should decode " <> show output <> " to " <> show input) $
        RLP.decode output `shouldBe` Just input

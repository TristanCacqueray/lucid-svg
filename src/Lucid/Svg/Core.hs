{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies      #-}

-------------------------------------------------------------------------------
-- |
-- Module      :  SVG.Core
-- Copyright   :  (c) 2015 Jeffrey Rosenbluth
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  jeffrey.rosenbluth@gmail.com
--
-- SVG elements.
-------------------------------------------------------------------------------

module Lucid.Svg.Core
( -- * Types
  Attribute
, Element
, ToElement(..)
, Term(..)
  -- * Combinators
, makeAttribute
, makeElement
, makeElementNoEnd
, makeXmlElementNoEnd
, with
  -- * Rendering
, renderBS
, renderToFile
, renderText
) where

import           Blaze.ByteString.Builder (Builder)
import qualified Blaze.ByteString.Builder as BB
import qualified Blaze.ByteString.Builder.Html.Utf8 as BB
import qualified Data.ByteString.Lazy as LB
import           Data.ByteString.Lazy (ByteString)
import           Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as M
import           Data.Monoid
import           Data.String
import           Data.Text (Text)
import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.Encoding as LT

--------------------------------------------------------------------------------
-- Types

-- | Attribute name value.
data Attribute = Attribute !Text !Text
  deriving (Show,Eq)

-- | Type of an SVG element.
newtype Element = Element (HashMap Text Text -> Builder)

instance Show Element where
  show e = LT.unpack . renderText $ e

instance Monoid Element where
  mempty = Element mempty
  mappend (Element e1) (Element e2) = Element (e1 <> e2)

instance IsString Element where
  fromString = toElement

-- | Things that can be converted to SVG elements.
class ToElement a where
  toElement :: a -> Element

instance ToElement String where
  toElement = Element . const . BB.fromHtmlEscapedString

instance ToElement Text where
  toElement = Element . const . BB.fromHtmlEscapedText

instance ToElement LT.Text where
  toElement = Element . const . BB.fromHtmlEscapedLazyText

-- | Used to make specific SVG element builders.
class Term result where
  -- | Used for constructing elements e.g. @term "p"@ yields 'Lucid.Html5.p_'.
  term :: Text -> [Attribute] -> result

instance (e ~ Element) => Term (e -> Element) where
  term name attrs e = with (makeElement name e) attrs

instance Term Element where
  term name attrs = with (makeXmlElementNoEnd name) attrs

--------------------------------------------------------------------------------
-- Combinators

-- | Make an attribute.
makeAttribute :: Text -- ^ Attribute name.
              -> Text -- ^ Attribute value.
              -> Attribute
makeAttribute = Attribute

-- | Union two sets of attributes and append duplicate keys.
unionAttrs :: HashMap Text Text -> HashMap Text Text -> HashMap Text Text
unionAttrs = M.unionWith (<>)

-- | Add a list of attributes to an element
with :: Element -> [Attribute] -> Element
with (Element e) attrs = Element $ \a ->
  e (unionAttrs (M.fromListWith (<>) (map toPair attrs)) a)
  where
    toPair (Attribute x y) = (x,y)

-- | Make an SVG element builder
makeElement :: Text -> Element -> Element
makeElement name (Element c) = Element $ \a -> go c a
  where
    go children attrs =
         s2b "<" <> BB.fromText name
      <> foldlMapWithKey buildAttr attrs <> s2b ">"
      <> children mempty
      <> s2b "</" <> BB.fromText name <> s2b ">"

-- | Make an SVG element builder with no end tag.
makeElementNoEnd :: Text -> Element
makeElementNoEnd name = Element $ \a -> go a
  where
    go attrs =
         s2b "<" <> BB.fromText name
      <> foldlMapWithKey buildAttr attrs <> s2b ">"

-- | Make an XML element with no end tag.
makeXmlElementNoEnd :: Text -> Element
makeXmlElementNoEnd name = Element $ \a -> go a
  where
    go attrs =
         s2b "<" <> BB.fromText name
      <> foldlMapWithKey buildAttr attrs <> s2b "/>"

-- | Folding and monoidally appending attributes.
foldlMapWithKey :: Monoid m => (k -> v -> m) -> HashMap k v -> m
foldlMapWithKey f = M.foldlWithKey' (\m k v -> m <> f k v) mempty

s2b :: String -> Builder
s2b = BB.fromString

-- | Build and encode an attribute.
buildAttr :: Text -> Text -> Builder
buildAttr key val =
  s2b " " <>
  BB.fromText key <>
  if val == mempty
    then mempty
    else s2b "=\"" <> BB.fromHtmlEscapedText val <> s2b "\""

--------------------------------------------------------------------------------
-- Rendering

-- | Render a 'Element' to lazy bytestring.
renderBS :: Element -> ByteString
renderBS (Element e) = BB.toLazyByteString $ e mempty

-- | Render a 'Element' to a file.
renderToFile :: FilePath -> Element -> IO ()
renderToFile fp = LB.writeFile fp . renderBS

-- | Reder an 'Element' to lazy text.
renderText :: Element -> LT.Text
renderText = LT.decodeUtf8 . renderBS

-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | Parsing for Clash's @clash-manifest.json@.

Clash emits one of these next to every generation. It is the authoritative
source of truth for port names, widths, directions, and clock domains —
much more stable than Verilator's own metadata (which has churned and,
as of Verilator 5.040, dropped @--xml-only@ entirely).

verilambda uses the manifest for two things:

  1. Build-time verification that a user's HKD port record actually
     matches the DUT's real ports. A mismatch is a type-level diff.
  2. Input to @verilambda-shim-gen@: the C++ shim's struct layout and
     step function are derived directly from @ports_flat@.

The parser is intentionally permissive — we only pick out the fields the
library cares about today. New top-level fields in future Clash versions
do not break parsing.
-}
module Verilambda.Manifest (
  Manifest (..),
  TopComponent (..),
  Port (..),
  Domain (..),
  ResetKind (..),
  ResetPolarity (..),
  ActiveEdge (..),
  InitBehavior (..),
  readManifest,
  decodeManifest,
) where

import Control.Exception (throwIO)
import Data.Aeson (
  FromJSON (parseJSON),
  Value (String),
  eitherDecodeStrict,
  withObject,
  (.!=),
  (.:),
  (.:?),
 )
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Text (Text)
import GHC.IO.Exception (IOErrorType (InappropriateType), IOException (..))
import Verilambda.Types (Direction)

{- | Top-level manifest. Only the fields the library uses today are
modelled; additional fields in a future Clash release are ignored.
-}
data Manifest = Manifest
  { manifestComponents :: [Text]
  , manifestDomains :: Map Text Domain
  , manifestTopComponent :: TopComponent
  , manifestVersion :: Text
  }
  deriving stock (Eq, Show)

instance FromJSON Manifest where
  parseJSON = withObject "Manifest" $ \o ->
    Manifest
      <$> o .: "components"
      <*> o .:? "domains" .!= mempty
      <*> o .: "top_component"
      <*> o .:? "version" .!= "unknown"

-- | The synthesized top entity — its generated name and flat port list.
data TopComponent = TopComponent
  { topName :: Text
  , topPorts :: [Port]
  }
  deriving stock (Eq, Show)

instance FromJSON TopComponent where
  parseJSON = withObject "TopComponent" $ \o ->
    TopComponent
      <$> o .: "name"
      <*> o .: "ports_flat"

-- | A single flat port as Verilog sees it.
data Port = Port
  { portName :: Text
  , portDirection :: Direction
  , portWidth :: Int
  , portIsClock :: Bool
  , portDomain :: Maybe Text
  , portTypeName :: Text
  }
  deriving stock (Eq, Show)

instance FromJSON Port where
  parseJSON = withObject "Port" $ \o ->
    Port
      <$> o .: "name"
      <*> o .: "direction"
      <*> o .: "width"
      <*> o .:? "is_clock" .!= False
      <*> o .:? "domain"
      <*> o .:? "type_name" .!= ""

-- (FromJSON Direction lives in Verilambda.Types, alongside the data
-- declaration, to avoid an orphan instance.)

{- | A clock domain as declared in the manifest. Captures enough to drive
 the SimM monad's default clock behaviour.
-}
data Domain = Domain
  { domainPeriod :: Int
  -- ^ period in picoseconds
  , domainResetKind :: ResetKind
  , domainResetPolarity :: ResetPolarity
  , domainActiveEdge :: ActiveEdge
  , domainInitBehavior :: InitBehavior
  }
  deriving stock (Eq, Show)

instance FromJSON Domain where
  parseJSON = withObject "Domain" $ \o ->
    Domain
      <$> o .: "period"
      <*> o .: "reset_kind"
      <*> o .: "reset_polarity"
      <*> o .: "active_edge"
      <*> o .: "init_behavior"

data ResetKind = Asynchronous | Synchronous
  deriving stock (Eq, Show, Read, Bounded, Enum)

instance FromJSON ResetKind where
  parseJSON = \case
    String "Asynchronous" -> pure Asynchronous
    String "Synchronous" -> pure Synchronous
    v -> fail $ "expected Asynchronous/Synchronous, got: " <> show v

data ResetPolarity = ActiveLow | ActiveHigh
  deriving stock (Eq, Show, Read, Bounded, Enum)

instance FromJSON ResetPolarity where
  parseJSON = \case
    String "ActiveLow" -> pure ActiveLow
    String "ActiveHigh" -> pure ActiveHigh
    v -> fail $ "expected ActiveLow/ActiveHigh, got: " <> show v

data ActiveEdge = Rising | Falling
  deriving stock (Eq, Show, Read, Bounded, Enum)

instance FromJSON ActiveEdge where
  parseJSON = \case
    String "Rising" -> pure Rising
    String "Falling" -> pure Falling
    v -> fail $ "expected Rising/Falling, got: " <> show v

data InitBehavior = Defined | Unknown
  deriving stock (Eq, Show, Read, Bounded, Enum)

instance FromJSON InitBehavior where
  parseJSON = \case
    String "Defined" -> pure Defined
    String "Unknown" -> pure Unknown
    v -> fail $ "expected Defined/Unknown, got: " <> show v

-- * Convenience entry points

{- | Parse a manifest from a ByteString. Returns 'Left' with an aeson
 error message on failure.
-}
decodeManifest :: BS.ByteString -> Either String Manifest
decodeManifest = eitherDecodeStrict

{- | Read and parse a manifest from disk. Throws 'IOException' on parse
 failure so calling code can wrap it in a user-friendly diff diagnostic.
-}
readManifest :: FilePath -> IO Manifest
readManifest path = do
  bytes <- BS.readFile path
  case decodeManifest bytes of
    Right m -> pure m
    Left err ->
      throwIO
        IOError
          { ioe_handle = Nothing
          , ioe_type = InappropriateType
          , ioe_location = "Verilambda.Manifest.readManifest"
          , ioe_description = "failed to parse clash-manifest.json: " <> err
          , ioe_errno = Nothing
          , ioe_filename = Just path
          }

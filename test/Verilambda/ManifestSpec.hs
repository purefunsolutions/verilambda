-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

-- | Tests for 'Verilambda.Manifest'.
module Verilambda.ManifestSpec (tests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertFailure, testCase, (@?=))
import Verilambda.Manifest (
  ActiveEdge (..),
  Domain (..),
  InitBehavior (..),
  Manifest (..),
  Port (..),
  ResetKind (..),
  ResetPolarity (..),
  TopComponent (..),
  decodeManifest,
 )
import Verilambda.Types (Direction (..))

tests :: TestTree
tests =
  testGroup
    "Verilambda.Manifest"
    [ testCase "parses the Blinky fixture end-to-end" test_parseBlinky
    , testCase "rejects unknown direction string" test_rejectBadDirection
    , testCase "rejects truncated JSON" test_rejectTruncated
    , testCase "accepts manifest with no domains field (permissive)" test_acceptNoDomains
    ]

fixturePath :: FilePath
fixturePath = "test/fixtures/blinky-manifest.json"

test_parseBlinky :: Assertion
test_parseBlinky = do
  bytes <- BS.readFile fixturePath
  case decodeManifest bytes of
    Left err -> assertFailure ("failed to parse Blinky fixture: " <> err)
    Right m -> do
      manifestComponents m @?= ["blinky"]
      topName (manifestTopComponent m) @?= "blinky"
      length (topPorts (manifestTopComponent m)) @?= 3

      -- Each port is exactly what Clash generated for the DE2 Blinky.
      let [p0, p1, p2] = topPorts (manifestTopComponent m)
      p0
        @?= Port
          { portName = "CLOCK_50"
          , portDirection = In
          , portWidth = 1
          , portIsClock = True
          , portDomain = Just "Dom50"
          , portTypeName = ""
          }
      p1
        @?= Port
          { portName = "KEY0"
          , portDirection = In
          , portWidth = 1
          , portIsClock = False
          , portDomain = Just "Dom50"
          , portTypeName = ""
          }
      p2
        @?= Port
          { portName = "LEDR"
          , portDirection = Out
          , portWidth = 8
          , portIsClock = False
          , portDomain = Nothing
          , portTypeName = "[7:0]"
          }

      -- Dom50 is the DE2's 50 MHz, async active-low — matches Blinky.hs.
      case Map.lookup "Dom50" (manifestDomains m) of
        Nothing -> assertFailure "Dom50 missing from domains"
        Just d -> do
          domainPeriod d @?= 20_000
          domainResetKind d @?= Asynchronous
          domainResetPolarity d @?= ActiveLow
          domainActiveEdge d @?= Rising
          domainInitBehavior d @?= Defined

test_rejectBadDirection :: Assertion
test_rejectBadDirection = do
  let junk =
        "{\"components\":[\"foo\"],\"top_component\":{\"name\":\"foo\",\"ports_flat\":"
          <> "[{\"name\":\"X\",\"direction\":\"sideways\",\"width\":1}]}}"
  case decodeManifest junk of
    Left _ -> pure ()
    Right _ -> assertFailure "expected parse failure on direction=sideways"

test_rejectTruncated :: Assertion
test_rejectTruncated = do
  let junk = "{\"components\":[\"foo\""
  case decodeManifest junk of
    Left _ -> pure ()
    Right _ -> assertFailure "expected parse failure on truncated JSON"

test_acceptNoDomains :: Assertion
test_acceptNoDomains = do
  let minimalJson =
        "{\"components\":[\"foo\"],\"top_component\":{\"name\":\"foo\",\"ports_flat\":[]}}"
  case decodeManifest minimalJson of
    Left err -> assertFailure ("should accept missing domains field: " <> err)
    Right m -> manifestComponents m @?= ["foo"]

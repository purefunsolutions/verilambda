-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

-- | Tests for 'Verilambda.BuildDriver'.
module Verilambda.BuildDriverSpec (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Verilambda.BuildDriver (BuildConfig (..))

tests :: TestTree
tests =
  testGroup
    "Verilambda.BuildDriver"
    [ unit_defaultFieldsRoundTrip
    ]

{- | BuildConfig is a plain record; this test just guards against
 accidentally removing a field from the public API.
-}
unit_defaultFieldsRoundTrip :: TestTree
unit_defaultFieldsRoundTrip = testCase "BuildConfig fields populate as expected" $ do
  let cfg =
        BuildConfig
          { bcShimGenExe = "verilambda-shim-gen"
          , bcManifestPath = "manifest.json"
          , bcTopName = "blinky"
          , bcVerilogFiles = ["blinky.v"]
          , bcOutDir = "dist/build/verilambda"
          }
  bcShimGenExe cfg @?= "verilambda-shim-gen"
  bcTopName cfg @?= "blinky"
  length (bcVerilogFiles cfg) @?= 1

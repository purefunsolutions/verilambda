-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

-- | Tasty entry point. Aggregates every test group in the library.
module Main where

import Test.Tasty (TestTree, defaultMain, testGroup)
import Verilambda.TypesSpec qualified

main :: IO ()
main = defaultMain allTests

allTests :: TestTree
allTests =
  testGroup
    "verilambda"
    [ Verilambda.TypesSpec.tests
    ]

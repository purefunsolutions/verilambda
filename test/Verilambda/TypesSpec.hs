-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

-- | Tests for 'Verilambda.Types'.
module Verilambda.TypesSpec (tests) where

import Hedgehog (Property, forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.Hedgehog (testProperty)
import Verilambda.Types (
  Bit,
  Direction (..),
  flipDirection,
  high,
  low,
 )

tests :: TestTree
tests =
  testGroup
    "Verilambda.Types"
    [ unit_bitConstants
    , unit_flipDirection
    , prop_flipDirectionInvolutiveExceptInOut
    , prop_directionRoundtripsShowRead
    ]

unit_bitConstants :: TestTree
unit_bitConstants = testCase "high and low are distinct Bit values" $ do
  assertBool "high /= low" (high /= low)

unit_flipDirection :: TestTree
unit_flipDirection = testCase "flipDirection swaps In and Out, leaves InOut alone" $ do
  flipDirection In @?= Out
  flipDirection Out @?= In
  flipDirection InOut @?= InOut

{- | Flipping direction twice is the identity, except for 'InOut' which is
  already its own fixed point. This makes it the identity everywhere.
-}
prop_flipDirectionInvolutiveExceptInOut :: TestTree
prop_flipDirectionInvolutiveExceptInOut =
  testProperty "flipDirection . flipDirection = id" prop
 where
  prop :: Property
  prop = property $ do
    d <- forAll Gen.enumBounded
    flipDirection (flipDirection d) === (d :: Direction)

-- | 'Direction' has Show + Read, so it should round-trip.
prop_directionRoundtripsShowRead :: TestTree
prop_directionRoundtripsShowRead =
  testProperty "read . show = id for Direction" prop
 where
  prop :: Property
  prop = property $ do
    d <- forAll (Gen.enumBounded @_ @Direction)
    read (show d) === d

-- Touches Bit so the import doesn't go unused before more suites land.
_unusedBit :: Bit
_unusedBit = low

-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

-- | Tests for 'Verilambda.Ports'.
module Verilambda.PortsSpec (tests) where

import Clash.Prelude (BitVector)
import Data.Proxy (Proxy (..))
import GHC.Generics (Generic)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Verilambda.Ports (PortMeta (..), Ports (portSpec))
import Verilambda.Types (Bit)

{- | A port record mirroring alterade2-flake's Blinky — three fields,
 two Bit inputs and an 8-bit vector output.
-}
data BlinkyPorts f = BlinkyPorts
  { clock_50 :: f Bit
  , key0 :: f Bit
  , ledr :: f (BitVector 8)
  }
  deriving stock (Generic)
  deriving anyclass (Ports)

-- | A wider DUT to exercise varied widths.
data WidePorts f = WidePorts
  { clk :: f Bit
  , reset_n :: f Bit
  , addr :: f (BitVector 32)
  , data_in :: f (BitVector 64)
  , data_out :: f (BitVector 64)
  , valid :: f Bit
  }
  deriving stock (Generic)
  deriving anyclass (Ports)

tests :: TestTree
tests =
  testGroup
    "Verilambda.Ports"
    [ testCase "BlinkyPorts yields three fields in declaration order" test_blinkyFields
    , testCase "BlinkyPorts widths are 1,1,8" test_blinkyWidths
    , testCase "WidePorts yields six fields in declaration order" test_wideFields
    , testCase "WidePorts preserves 32/64-bit widths" test_wideWidths
    ]

test_blinkyFields :: IO ()
test_blinkyFields =
  fmap pmName (portSpec (Proxy @BlinkyPorts))
    @?= ["clock_50", "key0", "ledr"]

test_blinkyWidths :: IO ()
test_blinkyWidths =
  fmap pmWidth (portSpec (Proxy @BlinkyPorts))
    @?= [1, 1, 8]

test_wideFields :: IO ()
test_wideFields =
  fmap pmName (portSpec (Proxy @WidePorts))
    @?= ["clk", "reset_n", "addr", "data_in", "data_out", "valid"]

test_wideWidths :: IO ()
test_wideWidths =
  fmap pmWidth (portSpec (Proxy @WidePorts))
    @?= [1, 1, 32, 64, 64, 1]

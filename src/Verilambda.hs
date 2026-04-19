-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | verilambda — Haskell bindings for Verilator simulation.

This is the umbrella module: a testbench usually needs nothing else.

@
import Verilambda

data BlinkyPorts f = BlinkyPorts
  { clock_50 :: f Bit
  , key0     :: f Bit
  , ledr     :: f (BitVector 8)
  } deriving stock Generic
    deriving anyclass Ports

main = runSim blinkyBackend do
  ...
@

The 'blinkyBackend' value is currently supplied by the user (hand-written
'foreign import' declarations). Once the Cabal hook layer lands,
@verilambda-shim-gen@ will emit the backend automatically for any DUT.
-}
module Verilambda (
  -- * Types
  Bit,
  BitVector,
  Signed,
  Unsigned,
  high,
  low,
  Direction (..),

  -- * HKD port records
  Ports (..),
  PortMeta (..),
  IsPortType (..),

  -- * Simulation monad
  SimM,
  runSim,
  Sim,
  SimBackend (..),
  tick,
  cycles,
  pokeState,
  peekState,
  modifyState,

  -- * Expectations
  shouldBe,
  shouldNotBe,
  shouldSatisfy,
  expectationFailure,
  ExpectationFailure (..),
)
where

import Verilambda.Expectations (
  ExpectationFailure (..),
  expectationFailure,
  shouldBe,
  shouldNotBe,
  shouldSatisfy,
 )
import Verilambda.Ports (IsPortType (..), PortMeta (..), Ports (..))
import Verilambda.Sim (
  Sim,
  SimBackend (..),
  SimM,
  cycles,
  modifyState,
  peekState,
  pokeState,
  runSim,
  tick,
 )
import Verilambda.Types (
  Bit,
  BitVector,
  Direction (..),
  Signed,
  Unsigned,
  high,
  low,
 )

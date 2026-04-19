-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | Core hardware-facing types used across verilambda.

Most types are re-exported from Clash's prelude so Clash user designs
interop trivially:

  * 'Bit' — a single wire, with 'high' and 'low' smart constructors
  * 'BitVector', 'Signed', 'Unsigned' — width-indexed integer types

verilambda adds one small type of its own: 'Direction', the port
direction tag used by 'Verilambda.Manifest' when describing a DUT's
signature.
-}
module Verilambda.Types (
  -- * Clash-compatible primitives
  Bit,
  BitVector,
  Signed,
  Unsigned,
  high,
  low,

  -- * Port direction
  Direction (..),
  flipDirection,
)
where

import Clash.Prelude (Bit, BitVector, Signed, Unsigned, high, low)
import Data.Aeson (FromJSON (parseJSON), Value (String))

-- | Direction of a DUT port, as recorded in the Clash manifest.
data Direction
  = -- | Consumed by the DUT; driven by the testbench.
    In
  | -- | Produced by the DUT; observed by the testbench.
    Out
  | -- | Bidirectional (tristate). Not supported in the v0.1 MVP.
    InOut
  deriving stock (Show, Read, Eq, Ord, Bounded, Enum)

-- The manifest encodes direction as lowercase "in"/"out"/"inout"; map
-- that back onto our Haskell enum. Lives here rather than in
-- Verilambda.Manifest to avoid an orphan instance.
instance FromJSON Direction where
  parseJSON = \case
    String "in" -> pure In
    String "out" -> pure Out
    String "inout" -> pure InOut
    v -> fail $ "expected direction string (in/out/inout), got: " <> show v

-- | Swap input/output. 'InOut' is fixed under this operation.
flipDirection :: Direction -> Direction
flipDirection In = Out
flipDirection Out = In
flipDirection InOut = InOut

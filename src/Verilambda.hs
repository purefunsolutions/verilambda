-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | Umbrella module — re-exports the common eDSL for writing Verilator
testbenches in Haskell. The public API grows here as the library modules
come online; right now the package has no exports.

Once the MVP lands, a typical import for a testbench is just:

@
import Verilambda
@

which should bring in @runSim@, @cycles@, @assertReset@, @shouldBe@,
@(.=)@, @withTrace@, and friends — nothing else from the library is
needed for the common case.
-}
module Verilambda () where

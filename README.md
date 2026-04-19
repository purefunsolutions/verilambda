<!--
SPDX-FileCopyrightText: 2026 Mika Tammi
SPDX-License-Identifier: MIT OR BSD-3-Clause
-->

# verilambda

Haskell bindings for [Verilator](https://verilator.org/) — write your hardware
testbenches in Haskell, run them at compiled-C++ speed.

**Status**: pre-release, under active development. First tagged release
(`v0.1.0`) is in progress; expect API churn until then. Targets Verilator
5.040+ only.

```haskell
{-# LANGUAGE OverloadedLabels, DataKinds, DeriveGeneric, DeriveAnyClass #-}

import Clash.Prelude (BitVector)
import Verilambda

data BlinkyPorts f = BlinkyPorts
  { clock_50 :: f Bit
  , key0     :: f Bit
  , ledr     :: f (BitVector 8)
  } deriving stock Generic
    deriving anyclass (Ports, ClockReset)

main :: IO ()
main = runSim @BlinkyPorts "Blinky" do
  assertReset
  cycles 4_194_304         -- 2^22 cycles, one LEDR tick at 50 MHz
  #ledr `shouldBe` 1
```

## Why

The existing [`clashilator`](https://hackage.haskell.org/package/clashilator)
package (April 2024) is largely dormant, uses Template Haskell, and degrades
Clash's `BitVector n` types to machine words at the FFI boundary. verilambda
aims to be:

- **Actively maintained** — the whole reason the project exists.
- **Type-preserving** — `BitVector 8` stays a `BitVector 8` all the way to the
  C++ call. The compiler catches width mismatches before the simulator does.
- **Ergonomic** — a 10-line monadic testbench body for the common case.
  Overloaded labels (`#ledr`) for port access, hspec-flavoured expectations,
  first-class property testing.
- **No Template Haskell** — port reflection happens via GHC Generics + the
  `barbies` higher-kinded-data pattern, not TH splices.
- **Modern Verilator** — 5.040+ only, no legacy compatibility shims.

## How it works

Three layers:

1. You declare your DUT's ports once as a higher-kinded data record.
1. At `cabal build` time, verilambda reads the Clash manifest, generates a
   thin C ABI shim, and invokes Verilator to compile it.
1. At runtime, a `SimM` monad exposes a clean API (`cycles`, `#port .= value`,
   `#port `shouldBe` value`, `withTrace`) over the compiled model.

No runtime parsing, no Template Haskell, no string-keyed port lookups.

## Requirements

- **GHC**: 9.10.3 or newer
- **Cabal**: 3.12+ (`build-type: Custom` path). Cabal 3.14+ required for the
  optional `build-type: Hooks` path.
- **Verilator**: 5.040 or newer
- **Linux**: macOS support is planned for v0.2

## Installation

Not yet on Hackage. For now, pin the repo as a flake input:

```nix
inputs.verilambda.url = "github:mikatammi/verilambda";
```

Or clone locally and reference via `cabal.project`:

```cabal
packages: . /path/to/verilambda
```

## Documentation

- [`PLAN.md`](./PLAN.md) — the design document this project is being built
  from; covers architecture, module layout, and the road to v0.1.0.
- `doc/architecture.md` — three-layer explainer with a pipeline diagram
  (coming with v0.1.0).
- `doc/integration.md` — decision tree for `build-type: Custom` vs.
  `build-type: Hooks` downstream (coming with v0.1.0).
- `examples/` — runnable examples that double as tests.

## License

Dual-licensed under either of:

- [MIT license](./LICENSE-MIT)
- [BSD-3-Clause license](./LICENSE-BSD)

at your option.

Note: verilambda links against Verilator's runtime, which is
[LGPLv3+artwork-2.0](https://github.com/verilator/verilator/blob/master/COPYING).
Downstream users should be aware of this dependency when distributing
binaries built with verilambda.

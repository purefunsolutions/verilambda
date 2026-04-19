<!--
SPDX-FileCopyrightText: 2026 Mika Tammi
SPDX-License-Identifier: MIT OR BSD-3-Clause
-->

# verilambda

Haskell bindings for [Verilator](https://verilator.org/) — write your hardware
testbenches in Haskell, run them at compiled-C++ speed.

**Status**: `v0.1.0` tagged; expect API churn across v0.x releases.
Targets Verilator 5.040+ only. CI runs on every commit against both
GHC 9.10 (Cabal 3.12) and GHC 9.12 (Cabal 3.14).

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

Two reasons, in order of importance:

1. **To build something we wanted to use.** Clash + Verilator is a
   productive combination for FPGA development, and we wanted a
   Haskell-native testbench library with very specific ergonomic and
   type-preservation properties. Writing one from scratch was the most
   direct way to get that.
1. **To experiment with Claude Opus 4.7's Haskell capabilities.** Most
   of the code, tests, Nix packaging, CI, and documentation in this
   repo was written through pair-programming with Claude Code running
   the Opus 4.7 1M-context model in max-effort mode. The library
   doubles as a real-world data point on how far current AI coding
   assistants can go on a non-trivial typed-Haskell project with
   native FFI, Cabal integration, and hardware-facing tooling.

A well-regarded alternative in the same design space is Gergő Érdi's
[`clashilator`](https://hackage.haskell.org/package/clashilator)
package. Projects that don't need the specific properties listed below
will likely be perfectly happy with it.

verilambda's concrete differentiators are:

- **Type-preserving** — `BitVector 8` stays a `BitVector 8` all the way to the
  C++ call. The compiler catches width mismatches before the simulator does.
- **Ergonomic** — a 10-line monadic testbench body for the common case.
  Overloaded labels (`#ledr`) for port access, hspec-flavoured expectations,
  first-class property testing.
- **No Template Haskell** — port reflection happens via GHC Generics + the
  `barbies` higher-kinded-data pattern, not TH splices. This avoids TH's
  usual trade-offs around cross-compilation and tooling friction.
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
inputs.verilambda.url = "github:purefunsolutions/verilambda";
```

Or clone locally and reference via `cabal.project`:

```cabal
packages: . /path/to/verilambda
```

## Integration: `build-type: Custom`

A downstream Haskell project can integrate the shim-gen + verilator
pipeline into `cabal build` via a small `Setup.hs`:

```haskell
-- Setup.hs
module Main (main) where
import Verilambda.Setup (verilambdaMainWithHooks, defaultBuildConfig, BuildConfig (..))

main :: IO ()
main = verilambdaMainWithHooks defaultBuildConfig
  { bcManifestPath = "clash-manifest.json"
  , bcTopName      = "blinky"
  , bcVerilogFiles = [ "verilog/blinky.v" ]
  }
```

The matching `.cabal` stanza:

```
build-type: Custom
custom-setup
  setup-depends: base, Cabal >= 3.0, verilambda, directory, process
```

`verilambdaMainWithHooks` runs shim-gen + verilator in the pre-build
hook and injects the resulting `extra-lib-dirs` + `extra-libs` into
every component's `BuildInfo` automatically. Requires
`verilambda-shim-gen` and `verilator` on `$PATH` at build time.

A `build-type: Hooks` adapter for Cabal 3.14+ is planned for v0.2 —
the `Verilambda.BuildDriver` module already factors out the pure
pipeline so both adapters can share it.

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

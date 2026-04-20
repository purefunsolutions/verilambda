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

## Using verilambda in your Clash project

Drop verilambda into an existing Clash project in three steps:

1. Let Clash emit Verilog + `clash-manifest.json` next to your design.
1. Pick one of the two integration modes below. Both wrap the same
   pure pipeline in `Verilambda.BuildDriver` (shim-gen → Verilator →
   `libV<top>.a`), injected into your binary via `extra-lib-dirs` +
   `extra-libs` at link time.
1. Write your testbench against the `Verilambda` API.

Either mode expects `verilambda-shim-gen` and `verilator` (≥ 5.040) on
`$PATH` at `cabal build` time. The flake's devShell
(`nix develop github:purefunsolutions/verilambda`) supplies both.

A reference project lives at [`examples/blinky/`](./examples/blinky) —
the Blinky counter from [alterade2-flake](https://github.com/purefunsolutions/alterade2-flake)
wired end-to-end through verilambda.

### Project layout

```
my-dut/
├── my-dut.cabal
├── cabal.project
├── Setup.hs              # classic Custom path, see below
├── SetupHooks.hs         # or: modern Hooks path, see below
├── src/
│   └── MyDut.hs          # your Clash design
├── verilog/
│   └── my_dut.v          # Clash-emitted: `clash --verilog MyDut`
├── clash-manifest.json   # Clash-emitted alongside the Verilog
└── test/
    └── Main.hs           # your verilambda testbench
```

### Classic `build-type: Custom` (Cabal 3.0+, any GHC ≥ 9.10)

This is the integration path shipped in `v0.1.0`. Tested end-to-end
against GHC 9.10.3 / Cabal 3.12 and GHC 9.12.2 / Cabal 3.14.

Your `my-dut.cabal`:

```cabal
cabal-version: 3.0
name:          my-dut
version:       0.1.0
build-type:    Custom

custom-setup
  setup-depends:
    , base
    , Cabal       >= 3.0 && < 4
    , directory
    , process
    , verilambda

test-suite my-dut-test
  type:           exitcode-stdio-1.0
  main-is:        Main.hs
  hs-source-dirs: test
  build-depends:
    , base
    , clash-prelude
    , verilambda
```

Your `Setup.hs` (four lines of wiring + three lines of DUT-specific
config):

```haskell
module Main (main) where

import Verilambda.Setup (BuildConfig (..), defaultBuildConfig, verilambdaMainWithHooks)

main :: IO ()
main = verilambdaMainWithHooks defaultBuildConfig
  { bcManifestPath = "clash-manifest.json"
  , bcTopName      = "my_dut"                   -- lower-cased Verilog module name
  , bcVerilogFiles = [ "verilog/my_dut.v" ]     -- one or more .v files
  }
```

What `verilambdaMainWithHooks` does on your behalf, at `cabal build`:

1. Runs `verilambda-shim-gen --manifest clash-manifest.json --out-dir dist/build/verilambda/cbits/`
   to produce a type-matched C ABI shim for your DUT.
1. Invokes `verilator --cc --build --trace -CFLAGS -fPIC` on your
   Verilog + the generated shim, producing `libVmy_dut.a` +
   `libverilated.a` under `dist/build/verilambda/obj_dir/`.
1. Injects `extra-lib-dirs=…/obj_dir` and
   `extra-libs=Vmy_dut, verilated, stdc++` into every component's
   `BuildInfo` via a `HookedBuildInfo` return, so GHC's linker picks
   them up transparently.

The rest of your project stays `build-type: Simple`-shaped — no
manual configure flags, no `--extra-lib-dirs` on the command line.

### Modern `build-type: Hooks` (Cabal 3.14+, GHC 9.12+) — preview

`build-type: Hooks` lands in verilambda **v0.2**. The planned API
mirrors the Custom path one-to-one, so code written against
`Verilambda.Setup` today migrates to `Verilambda.Setup.Hooks` with a
single `import` change.

Your `my-dut.cabal`:

```cabal
cabal-version: 3.14
name:          my-dut
version:       0.1.0
build-type:    Hooks

custom-setup
  setup-depends:
    , base
    , Cabal       >= 3.14 && < 4
    , verilambda
```

Your `SetupHooks.hs` (no `Setup.hs` needed at all):

```haskell
module SetupHooks (setupHooks) where

import Distribution.Simple.SetupHooks (SetupHooks)
import Verilambda.Setup.Hooks (BuildConfig (..), defaultBuildConfig, verilambdaSetupHooks)

setupHooks :: SetupHooks
setupHooks = verilambdaSetupHooks defaultBuildConfig
  { bcManifestPath = "clash-manifest.json"
  , bcTopName      = "my_dut"
  , bcVerilogFiles = [ "verilog/my_dut.v" ]
  }
```

Until v0.2 ships, Cabal 3.14+ users should stay on the Custom path
above — it works unchanged under Cabal 3.14 (CPP-guarded
`makeSymbolicPath` handles the API difference internally), and CI
tests it on GHC 9.12.2 (`blinky-sim-ghc912-builds` flake check).

### Writing the testbench

Today, testbenches supply a `SimBackend` value — a record of
`foreign import ccall` functions against the generated shim's C ABI.
See [`examples/blinky/src/Main.hs`](./examples/blinky/src/Main.hs) for
a working end-to-end example (8 FFI declarations, one HKD port record,
a `SimM` body). v0.2 will fold this boilerplate into `shim-gen`'s
Haskell-emitting pass, at which point the 10-line example at the top
of this README becomes the common case.

## Documentation

- [`PLAN.md`](./PLAN.md) — the design document this project is being
  built from; covers architecture, module layout, and the road to
  v0.1.0.
- [`examples/blinky/`](./examples/blinky) — a runnable reference
  integration. `nix run .#blinky-sim` prints the LEDR transition table
  for the Blinky design; `nix flake check` proves it matches
  byte-for-byte against the Verilator C++ and GHDL VHDL simulators in
  alterade2-flake.

## License

Dual-licensed under either of:

- [MIT license](./LICENSES/MIT.txt)
- [BSD-3-Clause license](./LICENSES/BSD-3-Clause.txt)

at your option.

Note: verilambda links against Verilator's runtime, which is
[LGPLv3+artwork-2.0](https://github.com/verilator/verilator/blob/master/COPYING).
Downstream users should be aware of this dependency when distributing
binaries built with verilambda.

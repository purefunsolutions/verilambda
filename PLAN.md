# verilambda — Haskell bindings for Verilator simulation

## Context

We built the Altera DE2 flake (previous plan; now shipped and working) and along the way realised the Haskell↔Verilator ecosystem has a real gap: **clashilator** (the existing Hackage package) is largely abandoned (last release April 2024, ~700 downloads, not tracking Verilator 5.040+), uses Template Haskell in questionable ways, degrades Clash `BitVector n` types to machine words at the FFI boundary, and relies on legacy Cabal `Setup.hs` hooks that were deprecated in Cabal 3.14.

We're going to build a replacement called **verilambda** — a new Haskell library that:

- **Targets Verilator 5.040+ only**, no legacy compatibility shims
- **Uses a type-based eDSL** (no Template Haskell anywhere)
- **Preserves Clash types** across the FFI boundary (Clash `BitVector 8` stays a `BitVector 8`, not a `Word8`)
- **Is actively maintained** from day one — that's the whole reason for existing
- **Is dual-licensed MIT + BSD-3** (permissive, matches task #8)
- **Is Clash-agnostic in naming** — works with any Verilator-synthesizable Verilog, Clash is just the first consumer

The first real consumer is `de2-blinky-sim-hs` back in alterade2-flake, mirroring the existing Verilator C++ (`de2-blinky-sim`) and GHDL VHDL (`de2-blinky-sim-ghdl`) simulators.

## Verified facts (April 2026)

From the research pass:

### Verilator 5.040 API surface (the stable subset)

- **Headers**: `verilated.h`, `verilated_vcd_c.h`, generated `V<module>.h`
- **Class shape (5.x stable)**: `V<module>` exposes public fields per port as smallest-fitting `uint8_t/16_t/32_t/64_t`, plus `eval()`, `final()`, and a `VerilatedContext*` it borrows
- **What we depend on**: port-field access (stable across 5.x), `eval()`, `final()`, `VerilatedVcdC` — all stable
- **What we deliberately avoid**: `--xml-only` (removed after 5.040), `--json-only` (unstable schema per Verilator's own docs), `___024root` internals (changes per release)

### `clash-manifest.json` is the metadata source

Clash emits `clash-manifest.json` next to every Verilog generation. Schema is stable, already classifies ports as In/Out/InOut with widths + clock flags. **This is our metadata source**, not Verilator's output. clashilator uses the same trick — we should too.

### Prior art line counts (a size budget)

- **clashilator**: ~616 LOC total (124 Haskell codegen + 171 Setup.hs + 80 Cabal + ~190 Mustache templates). Whole project is a preprocessor, not a library.
- **inline-verilog** (Mazzoli 2025, in fpco/inline-c): 391 LOC single file, TH-based, combinational only.
- **clash-cosim** (in clash-compiler): 1200+ LOC, heavy TH, VPI subprocess model, not Verilator-focused.

Our MVP should land around **~800 LOC of Haskell + ~100 LOC of C++ template**, comparable to clashilator but cleaner: no TH, no Mustache, no hsc2hs.

### Type-level patterns worth reusing

- **`barbies`** HKD: `data Ports f = Ports { clk :: f Bit, ledr :: f (BitVector 8) }` → one declaration gives you `Ports Identity` (values), `Ports Ptr` (pointers), `Ports (Const Text)` (metadata) for free.
- **`derive-storable`**: GHC.Generics-derived `Storable` instances, no hsc2hs.
- **DataKinds + `Symbol`** for port names at the type level, paired with `OverloadedLabels` for `#clk` access.
- **`generics-sop`** for structural folding over records when HKD isn't enough.

## Design decisions

1. **Location**: new sibling flake repo at `/home/mika/verilambda/`. Pre-created as empty git repo, no commits yet. alterade2-flake takes it as a flake input once the first release tag exists.
2. **Name**: `verilambda` (Verilator + λ). Package name `verilambda` on Hackage.
3. **Port DSL**: HKD records via `barbies`. Default choice; no TH, fewest user keystrokes, best ergonomics.
4. **GHC floor**: **9.10.3** (the version nixpkgs 25.11's `haskellPackages` defaults to, and the GHC alterade2-flake's Clash 1.8.4 builds against). No reason to exclude users stuck on current-stable nixpkgs. Test matrix should also cover 9.12.4 when practical.
5. **Build-type — verilambda itself**: `Custom` with a minimal `Setup.hs` (Cabal 3.12 compatible, works on GHC 9.10). Rationale: `build-type: Hooks` needs Cabal 3.14+ (GHC 9.12+), which we explicitly can't require as baseline. Setup.hs will be ~60 lines, mirroring clashilator's shape but without Mustache/hsc2hs.

5b. **Build-type — downstream consumers**: verilambda exposes **both** integration APIs so downstream projects can pick the one that fits their Cabal:
   - `Verilambda.Setup` — classic UserHooks-based API. Works with Cabal 3.0+. Users put `build-type: Custom` in their `.cabal` and a 5-line `Setup.hs` that calls `verilambdaMainWithHooks`.
   - `Verilambda.Setup.Hooks` — modern BuildHooks API. CPP-guarded with `#if MIN_VERSION_Cabal(3,14,0)`, so the module only compiles when verilambda itself was built against Cabal 3.14+. Users put `build-type: Hooks` and `hooks-executable: verilambda-hooks` in their `.cabal`.
   - Both APIs wrap the same underlying `runShimGen` + `invokeVerilator` functions (exposed as `Verilambda.BuildDriver` for ultra-custom setups).
   - Documented side-by-side in `doc/integration.md` with a "which one do I want?" decision tree.
6. **License**: MIT OR BSD-3-Clause dual from day 1.
7. **FFI strategy**: auto-generate a thin C++ shim from the Clash manifest at build time; the shim exposes a C ABI (`step`, `reset`, `trace_start`, `trace_dump`). Haskell side uses `foreign import ccall` against that C ABI.
8. **Type preservation**: at the Haskell layer, ports stay as Clash types (`Bit`, `BitVector n`, `Signed n`, `Unsigned n`). Coerce-based zero-cost conversions at the FFI boundary. The C ABI sees fixed-width `uint8_t`/`uint16_t`/`uint32_t`/`uint64_t`; the Haskell layer wraps them in the strongly-typed Clash newtypes.
9. **Metadata source**: `clash-manifest.json`. We parse it with `aeson`. If a non-Clash user wants to use verilambda with hand-written Verilog, they supply their own tiny manifest — documented format.
10. **Test framework**: **Tasty** as the aggregator, with `tasty-hunit` (unit), `tasty-quickcheck` (property, historical), `tasty-hedgehog` (property, modern alternative), and `tasty-golden` (C++ shim codegen tests). Both property-testing styles work under one runner. `cabal test` runs everything; coverage via `cabal test --enable-coverage` + `hpc markup`.
11. **Coverage target**: aim for 100% line + branch coverage on the Haskell side, firm floor **90%**. The C++ shim is generated code; we cover it indirectly through integration tests. CI fails if coverage drops below 90%.
12. **Examples as tests**: under `examples/`, each example is a runnable Cabal target with its own assertions. A top-level `cabal test` in verilambda runs them all as test cases — so examples can't rot. Every example covers at least one distinct feature: Blinky (counter + reset), FIFO (multi-input, buffered output), Mux (enum-ish inputs, etc.).

## Code quality & ergonomics (non-negotiable)

This library exists to be *nice to use*, not just to work. The whole reason to replace clashilator is ergonomics. The user-facing API and the internal code should both reflect that:

**User-facing ergonomics**:
- **One-record port spec** — users declare their DUT ports once as a HKD record and never re-state port names, widths, or directions anywhere else in their code. No duplicated manifest YAML, no port-list typeclass instances to hand-write, no string-keyed lookups at the call site.
- **The `SimM` monad reads like prose** — `runSim`, `cycles`, `assertReset`, `shouldBe` are common-English verbs and nouns. A reader who doesn't know the library can still tell what a testbench does on first read.
- **Overloaded labels for ports** — `#ledr`, `#clock_50` refer to the HKD record fields at the type level. Typos are compile-time errors. No stringly-typed lookups anywhere user code touches.
- **Hspec-flavoured expectations** — `shouldBe`, `shouldSatisfy`, `shouldBeIn`, `shouldChangeAfter` read like specs, work in both unit and property tests.
- **Single namespace import** — most testbenches import just `import Verilambda` (the umbrella module) and nothing else from our library. Barbies / generics / FFI are implementation details hidden behind the umbrella.
- **Strong types at every boundary** — `BitVector 8` stays a `BitVector 8`. `Bit` stays a `Bit`. No `Word8`-flavoured "close enough" types leaking into user code. The compiler catches width mismatches before the C ABI does.
- **Clear errors** — manifest/port-record mismatches surface at `cabal build` time with a human-readable diff ("expected port `CLOCK_50` at position 0, width 1; got port `clk` at position 0, width 1"), not as a C segfault at runtime.
- **Minimal ceremony** — the shortest useful testbench is ≤ 10 lines of `SimM` body plus imports. No manual bracket setup for the simplest case.
- **Progressive disclosure** — common case is trivial, advanced cases are possible. Raw pointer access is exposed via `Verilambda.FFI` for users who need to drop into custom C logic, but they never have to touch it for standard workflows. HKD/barbies machinery is in `Verilambda.Ports` for library authors; user testbenches never see `FunctorB` etc.
- **No orphan instance pollution** — everything the user needs to derive on their port record is re-exported from `Verilambda` with standard `deriving stock`/`deriving anyclass` idioms.

**Internal code quality**:
- **Readable over clever** — prefer straight-line `IO` with named helper functions over mega-`do` blocks. Prefer explicit `Data.ByteString` / `Data.Text` operations over ad-hoc string munging. Comments explain *why*, not *what*.
- **Small modules** — each module has one concept. If a module exceeds ~300 lines, it splits. `Manifest.hs` parses manifests; it does not also emit C++.
- **No Template Haskell anywhere** — stated design constraint; enforced by code review.
- **No CPP outside the `Setup.Hooks` Cabal-version guard** — CPP is a smell; only use it where we can't avoid it.
- **Pure core, IO at the edges** — `BuildDriver`, `Manifest`, `Ports`, `Storable` are pure. `Sim`, `Trace` wrap `IO`. This is the only axis of separation that matters; respect it.
- **Haddock on every exported identifier** — no naked type signatures in the public API. Every `Sim.step`, `Sim.peek`, etc. has a one-paragraph explanation with a usage example.
- **Formatting**: `fourmolu` + `treefmt` run on every save. Consistent style from day one so diffs stay meaningful.
- **Lints**: `hlint` clean, with a committed `.hlint.yaml` that documents any project-specific rules.
- **Naming**: verbs for actions (`runFor`, `pokeInputs`), nouns for values (`Sim`, `Ports`), adjectives prefix flags (`dirtyBuild`). No Hungarian notation.

**Documentation ergonomics**:
- README opens with a 15-line working example, not a feature list.
- Each module's header Haddock explains *what problem this module solves*, not *what this module contains*.
- `doc/architecture.md` has a diagram (ASCII or `.svg`) of the three layers — nothing replaces a picture for "how does this fit together".

## Formatters & linters (treefmt-nix, one runner for everything)

`nix/treefmt.nix` wires up a single `nix fmt` entry point + a `nix flake check` that verifies the tree is clean. All tools are the most modern variants available in nixpkgs 25.11:

**Nix**:
- **`alejandra`** — opinionated Nix formatter; zero-config, consistent with alterade2-flake
- **`deadnix`** — flags and removes unused Nix bindings / dead branches
- **`statix`** — Nix anti-pattern linter (e.g. `with`-shadowing, legacy idioms)

**Haskell**:
- **`fourmolu`** — the actively-maintained fork of ormolu. Currently the Haskell-community default; configurable via `fourmolu.yaml`. Committed config sets `indentation: 2`, `comma-style: leading`, `import-export-style: diff-friendly`, `respectful: true`.
- **`hlint`** — the canonical Haskell linter. Run both in `treefmt` (as a check) and in HLS (interactively). Committed `.hlint.yaml` with project-specific rule adjustments (e.g. allow `Data.Map.Strict as Map` even when strict isn't required).
- **`stylish-haskell`** — deliberately **NOT** used. fourmolu now covers import formatting comprehensively; two formatters fighting each other is a footgun.

**Cabal**:
- **`cabal-fmt`** — formats `.cabal` files consistently. Keeps `build-depends` alphabetised with trailing commas, avoids reflow noise.

**C++** (for the shim template + any hand-written C):
- **`clang-format`** — formats `shim.cpp.template` and any literal C++ strings. Uses a `.clang-format` committed at repo root with `BasedOnStyle: LLVM`, `IndentWidth: 2`.

**Shell** (for the one or two small helper scripts):
- **`shellcheck`** — lints bash. Mandatory on anything that goes into `runtimeInputs` of a `writeShellApplication`.
- **`shfmt`** — formats bash consistently.

**Markdown** (for `doc/`, `README.md`, `PLAN.md`):
- **`mdformat`** — light, consistent Markdown formatting. Configured not to reflow tables or lists aggressively so diffs stay meaningful.

**Everything together** in `nix/treefmt.nix`:

```nix
treefmt.config = {
  programs = {
    alejandra.enable     = true;
    deadnix.enable       = true;
    statix.enable        = true;
    fourmolu.enable      = true;
    cabal-fmt.enable     = true;
    clang-format.enable  = true;
    shellcheck.enable    = true;
    shfmt.enable         = true;
    mdformat.enable      = true;
  };
  # hlint runs as a separate check (not a formatter), wired in checks.nix
  settings.formatter.hlint-check = {
    command = "hlint";
    options = ["--no-exit-code"];   # report, don't fail formatter
    includes = ["*.hs"];
  };
};
```

**`nix flake check`** runs:
1. `treefmt --ci` — fails if any file would be reformatted
2. `hlint src/ test/ examples/` — fails on warning-severity issues (upgraded from hlint's default)
3. `hpc` coverage threshold check (separate script in `nix/checks.nix`)
4. `cabal test` via `haskellPackages.buildFromCabalSdist` — the standard flake-check wrapper

**CI rule**: every PR must be `nix flake check`-clean before merge. No `-- HLINT` pragmas without a comment explaining why.

## Repo layout

```
verilambda/
├── PLAN.md                       # copy of this plan, committed early as the north-star doc
├── flake.nix                     # flake-parts, matches nix-flake-base convention
├── flake.lock
├── README.md                     # what + why, small example; first file ever committed
├── CLAUDE.md
├── LICENSE-MIT                   # standard MIT text (Mika Tammi, 2026)
├── LICENSE-BSD                   # BSD-3-Clause text
├── verilambda.cabal              # build-type: Custom, cabal-version: 3.0, GHC2021, base>=4.20 && <5
├── Setup.hs                      # ~60 LOC: defaultMainWithHooks + preBuild hook invoking shim-gen
├── nix/
│   ├── default.nix
│   ├── devshell.nix              # ghc910, cabal-install, HLS, fourmolu, hlint,
│   │                             # cabal-fmt, clang-format, verilator 5.040+, treefmt
│   ├── checks.nix                # treefmt-nix check + hpc coverage threshold + hlint
│   └── treefmt.nix               # see "Formatters & linters" section below
├── pkgs/
│   └── default.nix               # packages: verilambda (lib), verilambda-shim-gen (bin)
├── src/
│   ├── Verilambda.hs             # umbrella module: re-exports the common eDSL (runSim,
│   │                             #  cycles, (.=), shouldBe, withTrace, assertReset...)
│   │                             #  90% of users import *only* this.
│   └── Verilambda/
│       ├── Sim.hs                # SimM monad (ReaderT SimEnv IO), runSim, withSim,
│       │                         # cycles, tick, assertReset, deassertReset
│       ├── MonadSim.hs           # MonadSim class for users who want to embed SimM
│       │                         # in their own transformer stacks
│       ├── Ports.hs              # HKD support: Ports class, port-name reflection via barbies;
│       │                         # IsLabel instances so #port_name works in SimM
│       ├── ClockReset.hs         # ClockReset class; auto-detection of clock/reset port fields
│       │                         # from naming conventions, with override hook
│       ├── Expectations.hs       # shouldBe, shouldSatisfy, shouldBeIn, shouldChange*,
│       │                         # (===), expectationFailure — hspec/hedgehog-flavoured
│       ├── Time.hs               # `cycles`, `for`, `until`, `waitUntil`; Cycles newtype
│       ├── FFI.hs                # foreign import ccall declarations, opaque Sim ptr
│       ├── Storable.hs           # GHC.Generics-derived Storable for HKD records (coerce-based)
│       ├── Trace.hs              # VCD support: withTrace bracket, dumpAt
│       ├── Manifest.hs           # parse clash-manifest.json, verify vs. type-level port spec
│       ├── Types.hs              # Bit (with `high`/`low` patterns), width-indexed types,
│       │                         # direction tags (In/Out/InOut)
│       ├── BuildDriver.hs        # pure: runShimGen, invokeVerilator (called by both Setup APIs)
│       ├── Setup.hs              # classic Cabal UserHooks API: verilambdaMainWithHooks
│       └── Setup/
│           └── Hooks.hs          # modern BuildHooks API, CPP-guarded for Cabal >= 3.14
├── shim-gen/
│   ├── Main.hs                   # CLI: verilambda-shim-gen --manifest … --out-dir …
│   ├── src/Verilambda/ShimGen/
│   │   ├── CppTemplate.hs        # C++ template as plain Haskell strings (no Mustache)
│   │   └── ManifestToPorts.hs    # parse manifest → emit C++ struct + step function
│   └── data/shim.cpp.template    # the raw template, read via Paths_verilambda_shim_gen
├── examples/
│   ├── blinky/                   # counter + reset: mirrors alterade2-flake's Blinky
│   │   ├── blinky.cabal
│   │   ├── design/Blinky.hs      # the Clash design
│   │   ├── test/Main.hs          # the testbench; cabal test target
│   │   └── clash-manifest.json   # committed for golden tests
│   ├── fifo/                     # multi-port, buffered output
│   │   └── …
│   └── mux/                      # enum-ish inputs
│       └── …
├── test/
│   ├── Main.hs                   # Tasty entry point, aggregates all test groups
│   ├── Verilambda/ManifestSpec.hs
│   ├── Verilambda/PortsSpec.hs   # HKD reflection round-trips (Hedgehog properties)
│   ├── Verilambda/StorableSpec.hs # width alignment, roundtrip through C ABI
│   ├── Verilambda/SimSpec.hs     # integration: simulate each example, assert outputs
│   └── ShimGenSpec.hs            # tasty-golden: lock in C++ output byte-for-byte
└── doc/
    ├── architecture.md           # three-layer explainer: HKD → shim-gen → Haskell FFI
    ├── integration.md            # decision tree: Custom vs Hooks, side-by-side snippets
    ├── porting-from-clashilator.md
    └── writing-new-examples.md   # how to add a new example that doubles as a test
```

## The eDSL: what user testbenches look like

**Design principle**: the simplest useful Blinky testbench is 10 lines of body, reads like prose, and requires zero pointer juggling. Everything past the minimum is additive — you opt into traces, properties, multiple DUTs, etc.

### Minimal example

```haskell
{-# LANGUAGE OverloadedLabels, DataKinds, DeriveGeneric, DeriveAnyClass #-}
module Main where

import Clash.Prelude       (BitVector)
import Verilambda

data BlinkyPorts f = BlinkyPorts
  { clock_50 :: f Bit
  , key0     :: f Bit
  , ledr     :: f (BitVector 8)
  } deriving stock Generic
    deriving anyclass (Ports, ClockReset)
    -- ^ `Ports`       derives HKD FunctorB/TraversableB/ApplicativeB
    --   `ClockReset`  auto-identifies clock_50 as the clock + key0 as
    --                 active-low reset (from name conventions); overridable.

main :: IO ()
main = runSim @BlinkyPorts "Blinky" do
  assertReset             -- pulses reset, settles clock
  cycles 4_194_304        -- advance 4.19M cycles (= 2^22, one LEDR tick)
  #ledr `shouldBe` 1      -- hspec-flavoured assertion, type-safe
```

That's the whole thing. No pointer types, no `peekOutputs`, no HKD pattern-match.

### Key eDSL choices

1. **`SimM` monad** — concrete `ReaderT SimEnv IO` under the hood. A type class `MonadSim` layered on top so users *can* run in `StateT`/`ExceptT` stacks if they need to, but the default is just: a monadic block.

2. **Overloaded labels for ports** — `#ledr`, `#clock_50`, `#key0`. Resolved at compile time against the HKD record's field names via `IsLabel` + `HasField` instances. Typos are type errors, not runtime lookups.

3. **Auto-detected clock and reset** — the `ClockReset` derived class scans field names against conventions (`clock*`, `clk*`, `reset*`, `rst*`, `*_n` = active-low). A user with unconventional names overrides explicitly:
   ```haskell
   instance ClockReset BlinkyPorts where
     clockPort = #clock_50
     resetPort = ActiveLow #key0
   ```

4. **Hspec-style expectations** — `shouldBe`, `shouldSatisfy`, `shouldBeIn`, `shouldChange`. Each works both as a direct call and as a Hedgehog/QuickCheck property body.
   ```haskell
   #ledr `shouldBe` 1
   #ledr `shouldSatisfy` (< 128)
   #ledr `shouldChangeAfter` (cycles (2^22))
   ```

5. **Readable time units** — `cycles n`, `for (cycles n)`, `until (sig `shouldBe` 1)`. No raw integers-with-comments-about-what-they-mean.
   ```haskell
   cycles 10
   for (cycles 100) (tick >> log "still going")
   until (#ledr `shouldEqual` 0xFF) tick
   ```

6. **Driving inputs** — assignment syntax via `(.=) :: Label name -> value -> SimM ()`:
   ```haskell
   #key0 .= low
   #clock_50 .= high     -- rare; usually you want `cycles` not manual clocking
   ```
   or bulk-set via an HKD value:
   ```haskell
   drive $ allPorts { key0 = high, clock_50 = low }
   ```

7. **VCD tracing as a bracket** — no mandatory argument threading:
   ```haskell
   main = runSim @BlinkyPorts "Blinky" do
     withTrace "blinky.vcd" do    -- all `cycles` inside emit to VCD
       assertReset
       cycles 20_000
   ```

8. **Property testing**, first-class:
   ```haskell
   prop_ledr_increments :: Property
   prop_ledr_increments = property $ runSim @BlinkyPorts "Blinky" do
     n <- forAll (Gen.integral (Range.linear 0 16))
     deassertReset
     cycles (2^22 * n)
     #ledr `shouldBe` fromIntegral (n .&. 0xFF)
   ```

9. **Introspection** — `peekAll :: SimM (AllPorts Identity)` returns the whole HKD record if a user wants it; but the common case uses per-port `#label` access and never touches the record as a value.

### Why a monad instead of a free algebra / applicative

Considered alternatives:
- **Free monad / freer** — pretty, but the cost is poor error messages and hard-to-inspect call stacks. Not worth it for this domain.
- **Applicative-only DSL** — would allow ahead-of-time optimisation of testbenches, but hardware testbenches inherently depend on observed values (branch on `peek` result, loop until a condition), so an applicative is too weak.
- **Indexed monads / linear types** — buys type-level guarantees like "you haven't deassertReset before reading output", but the complexity tax on users is steep.

Concrete `ReaderT SimEnv IO` wins on: IDE tooling works perfectly, stack traces point at the real callsite, `liftIO` trivially interops with any other Haskell IO.

### What gets generated at build time

`"Blinky"` in `runSim @BlinkyPorts "Blinky"` is a string identifying a build-time artifact. At `cabal build`:

1. Read the user's `clash-manifest.json` (looked up via custom cabal field `x-verilambda-manifest` pointing at the manifest file).
2. **Verify the `BlinkyPorts` HKD record matches the manifest at the type level** — field names, widths, directions. Mismatch fails the build with a diff:
   ```
   Port mismatch between BlinkyPorts and clash-manifest.json:
     field `ledr` declared as `f (BitVector 8)` but manifest says width=7
   ```
3. Run `verilambda-shim-gen --manifest … --port-spec …` to emit `BlinkyShim.{cpp,h}`.
4. Invoke `verilator --cc --exe --build -CFLAGS='-fPIC'` → `libVBlinky.a`.
5. Patch `BuildInfo`: add `extra-libs`, `extra-lib-dirs`, `include-dirs`.

User's Haskell code sees only the clean API; codegen is invisible except in build output.

### Full-featured example (advanced use)

For contrast, here's a testbench that uses multiple features at once:

```haskell
import Verilambda
import Hedgehog ((===), forAll, property, Property)
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

main :: IO ()
main = defaultMain
  [ testProperty "LEDR increments exactly every 2^22 cycles" prop_ledr
  , testCase     "KEY0 press resets counter to 0"          unit_reset
  ]

prop_ledr :: Property
prop_ledr = property $ runSim @BlinkyPorts "Blinky" do
  deassertReset
  n <- forAll (Gen.integral (Range.linear 0 32))
  cycles (2^22 * n)
  #ledr === fromIntegral (n .&. 0xFF)

unit_reset :: IO ()
unit_reset = runSim @BlinkyPorts "Blinky" do
  withTrace "reset-test.vcd" do
    deassertReset
    cycles 4_194_304
    #ledr `shouldBe` 1
    assertReset
    cycles 10
    #ledr `shouldBe` 0           -- reset clears the counter
```

No pattern matches on the HKD, no explicit pointer handling, the DUT identifier appears once, property + unit tests share the same `SimM` body shape.

## Bootstrap workflow (what I do first, in order)

The git repo at `/home/mika/verilambda/` is pre-created and empty (no commits yet). I execute in this exact order, one clean commit per logical unit:

1. **Copy this plan to `PLAN.md`** in the repo root. This is step zero — the plan goes into the repo as its own file before code does, so we can reference it throughout.
2. **Write `README.md`** — concise project pitch (name, tagline, 5-line example, license badges, install-from-Hackage note). **Commit as "Initial README"** — this is the first commit of the repo; it contains README.md only.
3. Second commit: `PLAN.md` + `LICENSE-MIT` + `LICENSE-BSD` + `.gitignore` (Haskell + Nix exclusions). Commit message: "Project charter and license texts".
4. Third commit: `flake.nix` + `nix/` skeleton from alterade2-flake's pattern. Commit: "Add flake.parts skeleton".
5. Fourth commit: empty `verilambda.cabal` + `Setup.hs` stub + `src/Verilambda.hs` with a stub `module Verilambda where` so `cabal build` resolves trivially. Commit: "Cabal skeleton".
6. Subsequent commits: add modules in order of dependency (`Types.hs`, `Manifest.hs`, `Ports.hs`, `Storable.hs`, `FFI.hs`, `Sim.hs`, `Trace.hs`). One commit per module with its accompanying tests. Message shape: "Add Verilambda.Manifest with parsing + property tests".
7. Commits for `shim-gen/` (CLI, template, ManifestToPorts).
8. Commits for each example (`blinky`, `fifo`, `mux`) — each a single commit adding the design, test, and manifest together.
9. Final MVP commit: "Integrate with alterade2-flake as de2-blinky-sim-hs" — in that other repo, adds the new sim package.
10. Tag v0.1.0 when `nix flake check` + `cabal test --enable-coverage` + integration in alterade2-flake all pass.

Rule: **every commit leaves the tree in a buildable state.** `cabal build` and `nix flake check` both succeed at every point in history. No WIP commits merged; squash locally if exploration is messy.

## Downstream integration (the two supported ways)

A consuming package picks whichever Cabal API matches their environment.

### Option A — classic `build-type: Custom` (works on Cabal 3.0+, GHC 9.0+)

```
-- myproject.cabal
build-type: Custom
custom-setup
  setup-depends: base, Cabal >= 3.0, verilambda

-- Setup.hs
import Verilambda.Setup (verilambdaMainWithHooks)
main = verilambdaMainWithHooks
```

That's the entire downstream integration — 4 lines of `Setup.hs`. Our hook reads the user's custom cabal fields (`x-verilambda-manifest`, `x-verilambda-top`, `x-verilambda-ports-module`), runs shim-gen + Verilator, patches BuildInfo.

### Option B — modern `build-type: Hooks` (Cabal 3.14+, GHC 9.12+)

```
-- myproject.cabal
cabal-version: 3.14
build-type: Hooks

-- SetupHooks.hs
import Verilambda.Setup.Hooks (verilambdaBuildHooks)
setupHooks = verilambdaBuildHooks
```

Same ergonomics, new API, no Setup.hs at all.

Both paths converge on `Verilambda.BuildDriver` — pure functions that don't depend on any Cabal API, so they're testable in isolation. If Cabal ever invents a third integration style, we add a third thin adapter module without touching the driver.

## Integration with alterade2-flake

Add a new sim package `pkgs/de2-blinky-sim-hs/` in alterade2-flake:

```
alterade2-flake/
└── pkgs/de2-blinky-sim-hs/
    ├── package.nix                 # callPackage building a Haskell exe
    ├── de2-blinky-sim-hs.cabal
    └── src/Main.hs                 # ~30 lines: the Haskell testbench
```

The flake.nix gains a new input:

```nix
verilambda.url = "github:mikatammi/verilambda";
# or during local dev:
# verilambda.url = "path:/home/mika/verilambda";
```

And `pkgs/default.nix` builds the Haskell test as a Cabal project using `haskellPackages.developPackage` or `haskell-flake`. This is the "eat your own dogfood" step — verilambda's first real-world test is the same Blinky design we already have.

## MVP scope

**In**:
- `Bit`, `BitVector n` port types (the 95% case)
- Single clock domain
- Explicit step / runFor / reset combinators
- VCD output (optional `Trace` record threaded through `withSim`)
- `clash-manifest.json`-driven build-time codegen
- Property-testable sim (exposes `Sim` as an opaque resource; users can wrap in `hedgehog` or `QuickCheck`)
- Works on Linux (macOS in theory, defer actual testing)

**Deliberately out**:
- Multi-clock domains (stub with `Unsupported` error; implement in v0.2)
- `Signed n` / `Unsigned n` port types (add before v0.1 if cheap)
- InOut ports / tristate
- DPI calls
- FST tracing (only VCD in MVP)
- Assertion bindings (SVA, PSL)
- Windows support
- Cosimulation vs. pure Haskell reference (that's what clash-cosim does; orthogonal)

## Critical files to reference

- `/home/mika/alterade2-flake/flake.nix` — flake skeleton pattern to copy
- `/home/mika/alterade2-flake/nix/{default,devshell,treefmt,checks}.nix` — flake-parts module layout
- `/home/mika/alterade2-flake/pkgs/de2-blinky-sim/tb_blinky.cpp` — reference for what C++ testbench code looks like (our generated shim is a stripped variant)
- `/home/mika/alterade2-flake/pkgs/de2-blinky/Blinky.hs` — the design we'll simulate first
- `/home/mika/alterade2-flake/result/verilog/Blinky.topEntity/clash-manifest.json` — **read this to anchor the manifest schema** before starting
- External: `github:gergoerdi/clashilator` (patterns — `src/Clash/Clashilator.hs` for the codegen structure, without copying its Mustache/hsc2hs approach)
- External: `github:verilator/verilator/docs/guide/connecting.rst` — the authoritative Verilator C++ API doc

## Verification

1. **Tasty test suite** (`cabal test --enable-coverage`):
   - `test/Verilambda/ManifestSpec.hs` — HUnit + golden: given sample `clash-manifest.json` inputs, expect fixed parsed-port structures.
   - `test/Verilambda/PortsSpec.hs` — Hedgehog properties: HKD reflection roundtrips, `PortsOf` class produces the field list matching `Generic`.
   - `test/Verilambda/StorableSpec.hs` — QuickCheck (via tasty-quickcheck): random port records roundtrip through `peek`/`poke` byte-identically.
   - `test/Verilambda/SimSpec.hs` — integration: for each example, builds the shim via shim-gen, invokes Verilator, opens the sim, steps it, checks outputs.
   - `test/ShimGenSpec.hs` — `tasty-golden`: lock the emitted C++ byte-for-byte so refactors to shim-gen don't silently change codegen.

2. **Coverage enforcement**:
   - `cabal test --enable-coverage` produces `.tix` files per test component.
   - A small script under `nix/checks.nix` runs `hpc markup` and fails if combined coverage drops below 90%.
   - Target 100% on `Verilambda.Manifest`, `Verilambda.Ports`, `Verilambda.Storable` (pure modules, no excuse); 80%+ on `Verilambda.Sim`, `Verilambda.Trace` (IO-heavy, harder to cover).

3. **Examples-are-tests**: each `examples/<name>/` has its own `cabal test` target. The root `verilambda.cabal` lists them via `common-stanza` so a single `cabal test all` runs the library tests + every example's assertions.

4. **Dogfood test** (in alterade2-flake):
   - `nix build .#de2-blinky-sim-hs`
   - `nix run .#de2-blinky-sim-hs` — exits 0, prints the same 4 LEDR transitions Verilator (`de2-blinky-sim`) and GHDL (`de2-blinky-sim-ghdl`) sims print.
   - `diff` the three sims' transition tables byte-for-byte (except format framing).

5. **Multi-GHC smoke check**: `nix flake check --impure` with a matrix `[ghc9103, ghc9124]` devShells, both should build.

6. **`nix flake check`** passes on verilambda itself + on alterade2-flake with the new input.

## Risks & fallbacks

- **Setup.hs being deprecated long-term**: Cabal 3.14+ now prefers `build-type: Hooks`. Our MVP can't require GHC 9.12 yet (alterade2-flake baseline is 9.10.3), so we stay on Custom. Migrate to Hooks as a follow-up when our GHC floor bumps. Document the planned migration in `doc/architecture.md`.
- **Manifest schema drift** between Clash versions: mitigate by pinning to Clash 1.8.x manifest shape in v0.1; add version detection in v0.2. Document the exact schema version we support.
- **HKD ergonomics for new Haskellers**: `barbies` has a learning curve (FunctorB/TraversableB etc.). Doc up front with a side-by-side example vs. a plain-record approach. If users really can't stomach HKD, offer an alternative `data In = In { ... }` / `data Out = Out { ... }` adapter pattern as a secondary API.
- **Verilator's `-CFLAGS -fPIC` for static linking into a Haskell binary** can trip up on macOS. Accept Linux-only in MVP; document macOS as v0.2.
- **License compatibility**: Verilator itself is LGPLv3+artwork-2.0. We link against it. MIT/BSD-3 dual-licensing the *bindings* is fine; we don't statically bundle Verilator's runtime, the user's binary picks it up at build time. Document this clearly so downstream users understand the LGPLv3 link.
- **No Clash-specific name but Clash-first test**: if a non-Clash Verilog user finds verilambda and expects it to work with hand-written `.v`, they need to provide a `clash-manifest.json`-shaped file. Document the schema as "verilambda's manifest, coincidentally the same shape as Clash's".

## Blog article (Pure Fun Solutions)

Alongside the library work, write a scientific-style article for the Pure Fun Solutions blog at `/home/mika/purefun-front/`.

**Repo state**: the user has pre-created the branch `blog_claude_building_verilator` (already checked out). Work proceeds there; no new branch needed.

**File location**: `src/blog/posts/building-verilator-haskell-bindings.md` (slug matches the branch intent). Following the convention set by the existing `src/blog/posts/hello-world.md`.

**Registration**: after writing the article, also:
1. Add the post to `src/blog/mod.rs` (metadata: title, date, slug, summary)
2. Register it in the project's build script (follows the pattern established for `hello-world`)
3. Verify the Yew frontend builds clean via the repo's standard build

**Article structure** — proper scientific article style, not the looser hello-world.md shape:

1. **Abstract** — 3–4 sentences only. States the contribution (new Haskell/Verilator bridge `verilambda`), the motivation (clashilator abandoned, ergonomics gap), and the concrete result (Blinky counter round-trips from Haskell source to LEDs on an Altera DE2 Cyclone II FPGA).

2. **Introduction** — short but a little longer than the abstract. 2–3 paragraphs. Context: FPGA development on NixOS in 2026, the Clash language, why simulation matters, what's broken in the current Haskell↔Verilator story.

3. **Background** — Clash, Verilator, the alterade2-flake project as predecessor work, how Clash emits Verilog and Verilator compiles it to fast C++. Brief tour of existing options (clashilator, clash-cosim, marlin-verilator in Rust) and why each is insufficient.

4. **Design** — the verilambda approach. Type-based eDSL (no TH), HKD port records via barbies, `SimM` monad, overloaded labels for ports, hspec-flavoured expectations, `clash-manifest.json` as the metadata source. Side-by-side comparison of clashilator's and verilambda's API at a small example.

5. **Implementation** — three-layer architecture: (i) HKD port records in user's Haskell, (ii) build-time shim generator emitting a C ABI, (iii) `SimM` monad exposing a nice API over the shim. Mention the dual support for `build-type: Custom` and `build-type: Hooks`.

6. **Evaluation** — the Blinky demonstration. Haskell source → Clash → Verilog → Verilator sim + Quartus synthesis → bitstream → DE2 board LEDs counting at 12 Hz. Include the transition-table byte-for-byte match between the Haskell, C++, and VHDL simulators and the physical board.

7. **Related Work** — brief, one paragraph each: clashilator (the prior art we replace), marlin-verilator (Rust equivalent that inspired several design choices), clash-cosim (complementary, not competing), inline-verilog (Mazzoli, 2025).

8. **Summary & Conclusions** — recap the contribution, emphasise the ergonomic gain ("10-line testbenches instead of 50"), identify future work (multi-clock domains, macOS port, Hackage publication).

**Style notes**:
- Writing register: neutral, descriptive, avoids first-person plural unless necessary. Passive voice acceptable where it reads naturally (matches the hello-world.md tone).
- Include at least one ASCII pipeline diagram (like hello-world.md's markdown→WASM flow) showing the Clash→Verilator→DE2 pipeline.
- Include one side-by-side code snippet comparing clashilator and verilambda at the same task.
- End-of-article metadata block listing tools used (Claude Code, verilambda, Clash 1.8.4, Verilator 5.040, Quartus II 13.0sp1, Altera DE2, NixOS 25.11, ghc 9.10.3).
- Length target: ~1500–2200 words total — longer than hello-world.md (~1100) because this is a more substantial technical contribution.

**Sequence** — the article gets written after the library MVP is demonstrably working. Reason: the article's Evaluation section depends on having the Blinky-on-DE2 pipeline functional end-to-end via verilambda. Writing before that risks describing something that doesn't yet exist.

## Follow-up work beyond MVP

- Port to Hackage (v0.1.0 release)
- `verilambda-quickcheck` companion package with ready-made property combinators (reset property, idempotence, functional equivalence vs. pure Haskell reference)
- `verilambda-fst` for FST-format waveforms (smaller than VCD for long sims)
- Multi-clock domain support
- macOS build path
- Migrate alterade2-flake's existing `de2-blinky-sim` (C++) and `de2-blinky-sim-ghdl` (VHDL) into a unified `de2-blinky-testsuite` running all three sims plus the Haskell one and cross-checking their transition tables byte-for-byte

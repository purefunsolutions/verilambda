# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT OR BSD-3-Clause
_: {
  perSystem = {
    self',
    pkgs,
    ...
  }: let
    inherit (pkgs) haskellPackages;

    # The library + shim-gen executable, built through cabal2nix so
    # dependency resolution goes through nixpkgs' haskellPackages.
    verilambda = haskellPackages.callCabal2nix "verilambda" ../. {};

    # Blinky example — the first end-to-end demo.
    blinky-sim = pkgs.callPackage ../examples/blinky/package.nix {
      inherit verilambda haskellPackages;
      inherit (self'.packages) verilambda-shim-gen;
    };

    # Alternative build on GHC 9.12 (ships Cabal 3.14, the minimum
    # required for `build-type: Hooks`). This is a smoke test — we
    # want to know if the library starts drifting against newer GHCs
    # so the v0.2 Hooks adapter has somewhere to stand.
    haskellPackages912 = pkgs.haskell.packages.ghc912.override {
      overrides = _hself: hsuper:
      # Clash 1.8.4 has upper bounds that exclude template-haskell
      # 2.23+ (GHC 9.12) and ghc-prim 0.13+ (also GHC 9.12). Jailbreak
      # to ignore those bounds, plus dontCheck to skip the
      # doctest-parallel mismatch in the test suite.
        pkgs.lib.mapAttrs
        (_name: drv:
          pkgs.haskell.lib.dontCheck
          (pkgs.haskell.lib.doJailbreak drv))
        {
          inherit (hsuper) clash-prelude clash-lib clash-ghc;
        };
    };
    verilambda-ghc912 = haskellPackages912.callCabal2nix "verilambda" ../. {};
    blinky-sim-ghc912 = pkgs.callPackage ../examples/blinky/package.nix {
      verilambda = verilambda-ghc912;
      haskellPackages = haskellPackages912;
      verilambda-shim-gen = verilambda-ghc912;
    };
  in {
    packages = {
      # Expose the library package itself for downstream Haskell consumers.
      inherit verilambda;

      # Just the shim-gen binary — standalone CLI useful on its own.
      verilambda-shim-gen = verilambda;
      # Both default to the same derivation since cabal2nix produces
      # one output containing lib + exe. Consumers pick the right
      # attribute (bin/verilambda-shim-gen for the CLI, lib/ for the
      # Haskell dependency).

      inherit blinky-sim blinky-sim-ghc912;

      default = blinky-sim;
    };

    apps = {
      blinky-sim = {
        type = "app";
        program = "${blinky-sim}/bin/blinky-sim";
      };
    };
  };
}

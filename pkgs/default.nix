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

      inherit blinky-sim;

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

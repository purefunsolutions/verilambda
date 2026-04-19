# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT OR BSD-3-Clause
#
# Flake checks:
#
#   * reuse-lint — enforce REUSE Specification 3.3 across the whole tree.
#
#   * blinky-sim-runs — build the Blinky example with the default GHC
#     (9.10.3, matching nixpkgs 25.11) and exercise it end-to-end.
#     Fails if the expected LEDR transitions are not observed.
#
#   * blinky-sim-ghc912 — build the same example with GHC 9.12 instead.
#     Guards against the library drifting out of compatibility with
#     newer compilers and provides a Cabal-3.14+ testbed for the
#     forthcoming build-type: Hooks adapter.
#
# All checks are part of `nix flake check` — every PR runs them
# automatically.
_: {
  perSystem = {
    self',
    pkgs,
    ...
  }: {
    checks = {
      # REUSE Specification 3.3 compliance — every source file either
      # carries inline SPDX tags or is covered by REUSE.toml, and every
      # license mentioned has its full text in LICENSES/.
      reuse-lint =
        pkgs.runCommand "reuse-lint" {
          nativeBuildInputs = [pkgs.reuse];
        } ''
          cp -r ${../.}/. ./work
          chmod -R +w ./work
          cd work
          reuse lint
          touch $out
        '';

      # Run the compiled Blinky sim and assert the transition table.
      blinky-sim-runs =
        pkgs.runCommand "blinky-sim-runs" {
          nativeBuildInputs = [self'.packages.blinky-sim];
        } ''
          blinky-sim > output.txt
          grep -q '4194303  00000001' output.txt \
            || { echo "missing LEDR 00000001 transition"; cat output.txt; exit 1; }
          grep -q '8388607  00000010' output.txt \
            || { echo "missing LEDR 00000010 transition"; cat output.txt; exit 1; }
          cp output.txt "$out"
        '';

      # Smoke-test the same example on GHC 9.12. Using haskell.packages.ghc912
      # gives us Cabal 3.14 which is what `build-type: Hooks` would need.
      blinky-sim-ghc912-builds =
        pkgs.runCommand "blinky-sim-ghc912-builds" {
          nativeBuildInputs = [self'.packages.blinky-sim-ghc912];
        } ''
          blinky-sim --help 2>/dev/null || true
          # The build alone proves the library + shim-gen + linker
          # pipeline works on the newer compiler. Exit success on the
          # mere existence of the binary.
          test -x ${self'.packages.blinky-sim-ghc912}/bin/blinky-sim
          echo "ok" > "$out"
        '';
    };
  };
}

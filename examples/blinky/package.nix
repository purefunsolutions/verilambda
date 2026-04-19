# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT OR BSD-3-Clause
#
# Nix derivation for the verilambda Blinky example, turning
# build-and-run.sh into a reproducible build.
#
# Pipeline:
#   1. verilambda-shim-gen     → cbits/verilambda_blinky_shim.{cpp,h}
#   2. verilator --cc --build  → obj_dir/{libVblinky,libverilated}.a
#   3. Haskell build           → $out/bin/blinky-sim, linked statically
#
# Wraps a 2-step mkDerivation: a pre-stage that produces the Verilator
# libraries, and a Haskell build that consumes them via extra-lib-dirs.
{
  stdenv,
  verilator,
  python3,
  haskellPackages,
  verilambda-shim-gen,
  verilambda,
}: let
  # Stage 1: run shim-gen + verilator to produce libVblinky.a + libverilated.a.
  blinky-shim = stdenv.mkDerivation {
    pname = "blinky-shim";
    version = "0.0.0";
    src = ./.;

    nativeBuildInputs = [verilator python3 verilambda-shim-gen];

    buildPhase = ''
      runHook preBuild
      mkdir -p cbits
      verilambda-shim-gen \
        --manifest clash-manifest.json \
        --out-dir cbits
      verilator --cc --build --trace \
        -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
        -CFLAGS -fPIC \
        --Mdir obj_dir \
        verilog/blinky.v \
        cbits/verilambda_blinky_shim.cpp
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib $out/include
      cp obj_dir/libVblinky.a $out/lib/
      cp obj_dir/libverilated.a $out/lib/
      cp cbits/verilambda_blinky_shim.h $out/include/
      runHook postInstall
    '';

    dontFixup = true;
  };

  # Stage 2: Haskell executable, pulling verilambda + blinky-shim at link time.
  hs = haskellPackages.callCabal2nix "verilambda-example-blinky" ./. {
    inherit verilambda;
  };
in
  hs.overrideAttrs (prev: {
    configureFlags =
      (prev.configureFlags or [])
      ++ [
        "--extra-lib-dirs=${blinky-shim}/lib"
        "--ghc-option=-optl-lVblinky"
        "--ghc-option=-optl-lverilated"
        "--ghc-option=-optl-lstdc++"
      ];

    meta = (prev.meta or {}) // {description = "verilambda Blinky end-to-end demo (ships the Haskell testbench as an executable)";};
  })

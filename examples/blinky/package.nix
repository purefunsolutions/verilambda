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

    # Copy sources into a fresh build tree rather than symlinking. Verilator
    # caches absolute paths of its source files into its generated Makefile,
    # and when the source is a symlink to a user-space working tree (e.g.
    # via a `path:` flake input), the cached path is the working-tree one —
    # which doesn't exist inside the Nix build sandbox. An explicit copy
    # forces verilator to record the sandbox path and keeps the build
    # hermetic.
    buildPhase = ''
      runHook preBuild
      export BUILD=$PWD/build
      rm -rf "$BUILD"
      mkdir -p "$BUILD/cbits" "$BUILD/verilog"
      cp clash-manifest.json "$BUILD/"
      cp verilog/blinky.v "$BUILD/verilog/"
      cd "$BUILD"
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
      cp $BUILD/obj_dir/libVblinky.a $out/lib/
      cp $BUILD/obj_dir/libverilated.a $out/lib/
      cp $BUILD/cbits/verilambda_blinky_shim.h $out/include/
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

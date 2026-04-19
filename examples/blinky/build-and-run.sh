#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT OR BSD-3-Clause
#
# Run this from inside verilambda's `nix develop` shell:
#
#     cd examples/blinky && ./build-and-run.sh
#
# Pipeline:
#   1. verilambda-shim-gen            → cbits/verilambda_blinky_shim.{cpp,h}
#   2. verilator + g++                → obj_dir/{libVblinky,libverilated}.a
#   3. cabal build --extra-lib-dirs   → Haskell exe linked against the libs
#   4. run                            → prints LEDR transitions, expects 4

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "== 1/3: verilambda-shim-gen"
mkdir -p cbits
cabal run --project-dir=../.. -v0 verilambda-shim-gen -- \
  --manifest "$HERE/clash-manifest.json" \
  --out-dir "$HERE/cbits"

echo "== 2/3: verilator --cc --build --trace"
rm -rf obj_dir
verilator \
  --cc --build --trace \
  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -CFLAGS "-fPIC -I$HERE/cbits" \
  --Mdir obj_dir \
  verilog/blinky.v \
  "$HERE/cbits/verilambda_blinky_shim.cpp"

echo "== 3/3: cabal build + run"
cabal build \
  --extra-lib-dirs="$HERE/obj_dir" \
  blinky-sim

echo "== Running blinky-sim"
cabal run \
  --extra-lib-dirs="$HERE/obj_dir" \
  blinky-sim

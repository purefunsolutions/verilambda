-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | Pure IO orchestration for the shim-gen → verilator pipeline.

This module is the thin layer that both 'Verilambda.Setup' (classic
Cabal @build-type: Custom@) and the future 'Verilambda.Setup.Hooks'
(Cabal 3.14+ @build-type: Hooks@) call into. It deliberately knows
nothing about the Cabal API — the adapters above it do all the
BuildInfo massaging.

The orchestration is exactly what @examples/blinky/build-and-run.sh@
and @examples/blinky/package.nix@ do, restated in Haskell so it can
be invoked from a user's @Setup.hs@ without shelling out to bash.
-}
module Verilambda.BuildDriver (
  BuildConfig (..),
  runShimGen,
  invokeVerilator,
  buildShim,
)
where

import Data.List (intercalate)
import System.Directory (createDirectoryIfMissing)
import System.Process (callProcess)

{- | Everything the build driver needs. Typically populated from
custom cabal fields or environment variables by the upstream adapter.
-}
data BuildConfig = BuildConfig
  { bcShimGenExe :: FilePath
  {- ^ Path to the @verilambda-shim-gen@ binary. Usually resolved from
  @$PATH@ by the Cabal setup hook, but can be an absolute path.
  -}
  , bcManifestPath :: FilePath
  -- ^ Path to the Clash @clash-manifest.json@ for the DUT.
  , bcTopName :: String
  {- ^ Lower-cased Verilog top name (e.g. @"blinky"@). Used to build
  the shim file name @verilambda_<top>_shim.cpp@.
  -}
  , bcVerilogFiles :: [FilePath]
  {- ^ Verilog sources to feed to verilator alongside the generated
  shim. Usually Clash's emitted @.v@ files.
  -}
  , bcOutDir :: FilePath
  {- ^ Where shim-gen writes its output (@shim.cpp@ + @shim.h@) and
  where verilator's @obj_dir/@ is rooted.
  -}
  }
  deriving stock (Show, Eq)

{- | Run @verilambda-shim-gen@ to produce @<outDir>/cbits/@ with the
shim header and source.
-}
runShimGen :: BuildConfig -> IO ()
runShimGen BuildConfig {..} = do
  let cbitsDir = bcOutDir <> "/cbits"
  createDirectoryIfMissing True cbitsDir
  callProcess
    bcShimGenExe
    [ "--manifest"
    , bcManifestPath
    , "--out-dir"
    , cbitsDir
    ]

{- | Invoke verilator to produce @<outDir>/obj_dir/libV<top>.a@ and
@libverilated.a@.
-}
invokeVerilator :: BuildConfig -> IO ()
invokeVerilator BuildConfig {..} = do
  let mdir = bcOutDir <> "/obj_dir"
      shim = bcOutDir <> "/cbits/verilambda_" <> bcTopName <> "_shim.cpp"
  callProcess
    "verilator"
    ( [ "--cc"
      , "--build"
      , "--trace"
      , "-Wno-WIDTHEXPAND"
      , "-Wno-WIDTHTRUNC"
      , "-CFLAGS"
      , "-fPIC"
      , "--Mdir"
      , mdir
      ]
        <> bcVerilogFiles
        <> [shim]
    )

{- | Full pipeline: shim-gen, then verilator. Convenience wrapper used
by the default Cabal pre-build hook.
-}
buildShim :: BuildConfig -> IO ()
buildShim cfg = do
  putStrLn $
    "[verilambda] building shim for DUT '"
      <> bcTopName cfg
      <> "' from manifest "
      <> bcManifestPath cfg
  runShimGen cfg
  putStrLn $ "[verilambda] invoking verilator on " <> intercalate ", " (bcVerilogFiles cfg)
  invokeVerilator cfg
  putStrLn "[verilambda] shim build complete."

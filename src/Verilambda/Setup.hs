-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause
{-# LANGUAGE CPP #-}

{- | Classic @build-type: Custom@ Cabal adapter for verilambda.

A downstream project opts in by putting

@
build-type: Custom
custom-setup
  setup-depends: base, Cabal >= 3.0, verilambda, directory
@

in its @.cabal@ file and this in its @Setup.hs@:

@
module Main (main) where
import Verilambda.Setup (verilambdaMainWithHooks, defaultBuildConfig)
main = verilambdaMainWithHooks defaultBuildConfig
  { bcManifestPath  = "clash-manifest.json"
  , bcTopName       = "blinky"
  , bcVerilogFiles  = [ "verilog/blinky.v" ]
  }
@

At @cabal build@ time we run @verilambda-shim-gen@ + @verilator@ into
@dist/build/verilambda/@, then inject the resulting @extra-lib-dirs@ +
linker flags into every component's 'BuildInfo' so @ghc --make@ can
resolve the @-lV<top>@ / @-lverilated@ / @-lstdc++@ libraries at link
time.

Cabal 3.14+ users should prefer 'Verilambda.Setup.Hooks' once it ships
— this module will still work, but the Hooks API is forward-looking.
-}
module Verilambda.Setup (
  verilambdaMainWithHooks,
  defaultBuildConfig,

  -- * Re-exports
  BuildConfig (..),
)
where

import Distribution.PackageDescription (
  BuildInfo (extraLibDirs, extraLibs),
  HookedBuildInfo,
  emptyBuildInfo,
 )
import Distribution.Simple (
  UserHooks (preBuild),
  defaultMainWithHooks,
  simpleUserHooks,
 )
#if MIN_VERSION_Cabal(3,14,0)
import Distribution.Utils.Path (makeSymbolicPath)
#endif
import Verilambda.BuildDriver (
  BuildConfig (..),
  buildShim,
 )

{- | A sensible starting point. The user overrides the two or three
 fields that are actually DUT-specific.
-}
defaultBuildConfig :: BuildConfig
defaultBuildConfig =
  BuildConfig
    { bcShimGenExe = "verilambda-shim-gen"
    , bcManifestPath = "clash-manifest.json"
    , bcTopName = "top"
    , bcVerilogFiles = []
    , bcOutDir = "dist/build/verilambda"
    }

{- | Main entry point for a downstream project's @Setup.hs@. Runs the
shim-gen + verilator pipeline in @preBuild@, then forwards to Cabal's
@defaultMain@. Emits the link flags needed for the DUT via the
'HookedBuildInfo' return.
-}
verilambdaMainWithHooks :: BuildConfig -> IO ()
verilambdaMainWithHooks cfg =
  defaultMainWithHooks
    simpleUserHooks
      { preBuild = \_args _bflags -> verilambdaPreBuild cfg
      }

verilambdaPreBuild :: BuildConfig -> IO HookedBuildInfo
verilambdaPreBuild cfg = do
  buildShim cfg
  let libPath = bcOutDir cfg <> "/obj_dir"
#if MIN_VERSION_Cabal(3,14,0)
      libDirs = [makeSymbolicPath libPath]
#else
      libDirs = [libPath]
#endif
      bi =
        emptyBuildInfo
          { extraLibDirs = libDirs
          , extraLibs =
              [ "V" <> bcTopName cfg
              , "verilated"
              , "stdc++"
              ]
          }
  pure (Just bi, [])

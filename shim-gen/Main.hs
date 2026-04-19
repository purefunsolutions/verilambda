-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | The @verilambda-shim-gen@ CLI. Reads a @clash-manifest.json@,
emits the C ABI header and C++ source for the DUT's shim.
-}
module Main (main) where

import Data.Text qualified as Text
import Data.Text.IO qualified as TIO
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Options.Applicative
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import Verilambda.Manifest (
  Manifest (manifestTopComponent),
  TopComponent (topName, topPorts),
  readManifest,
 )
import Verilambda.ShimGen.CppTemplate (
  ShimGenInput (..),
  renderShimHeader,
  renderShimSource,
 )

data Options = Options
  { optManifestPath :: FilePath
  , optOutDir :: FilePath
  }

optionsParser :: Parser Options
optionsParser =
  Options
    <$> strOption
      ( long "manifest"
          <> metavar "PATH"
          <> help "Path to clash-manifest.json for the DUT"
      )
    <*> strOption
      ( long "out-dir"
          <> metavar "PATH"
          <> help "Directory to write the generated shim files into"
      )

main :: IO ()
main = do
  -- Force UTF-8 file I/O even in sandboxed builds (NixOS nix-build,
  -- containerised CI) where the default locale is often POSIX/C.
  setLocaleEncoding utf8
  opts <-
    execParser $
      info
        (optionsParser <**> helper)
        ( fullDesc
            <> progDesc "Generate a C/C++ shim around a Clash-synthesised DUT for Verilator."
            <> header "verilambda-shim-gen — part of the verilambda library"
        )
  manifest <- readManifest (optManifestPath opts)
  let top = manifestTopComponent manifest
      input =
        ShimGenInput
          { sgiTopName = topName top
          , sgiPorts = topPorts top
          }
      headerText = renderShimHeader input
      sourceText = renderShimSource input
      base = "verilambda_" <> Text.unpack (Text.toLower (topName top)) <> "_shim"
      headerPath = optOutDir opts </> (base <> ".h")
      sourcePath = optOutDir opts </> (base <> ".cpp")
  createDirectoryIfMissing True (optOutDir opts)
  TIO.writeFile headerPath headerText
  TIO.writeFile sourcePath sourceText
  putStrLn $ "Wrote " <> headerPath
  putStrLn $ "Wrote " <> sourcePath

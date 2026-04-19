-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause
--
-- Stub Setup.hs. Passes through to Cabal's defaultMain for now. Will be
-- replaced by verilambda's own `verilambdaMainWithHooks` entry point once
-- the build-driver + shim-gen modules come online.
module Main where

import Distribution.Simple

main :: IO ()
main = defaultMain

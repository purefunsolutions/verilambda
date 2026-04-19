-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | End-to-end verilambda demo: simulate the Blinky counter from
@alterade2-flake@'s DE2 design and check that the 8 red LEDs transition
at the same cycle boundaries the physical board does.

This example is also the first real linker-level integration test of
verilambda. It links against the Verilator-compiled @libVblinky.a@ plus
the auto-generated @verilambda_blinky_shim.o@, driven through eight
hand-written @foreign import ccall@ declarations.

When @verilambda-shim-gen@ grows a Haskell-emitting pass (v0.2), the
foreign-import block below will be generated automatically.
-}
module Main (main) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.Word (Word64, Word8)
import Foreign.C.String (CString, withCString)
import Foreign.Ptr (Ptr)
import Foreign.Storable (Storable (..))
import GHC.Generics (Generic)
import Verilambda

-- * FFI — hand-written bindings to the verilambda-shim-gen output

foreign import ccall unsafe "verilambda_blinky_new"
  c_blinky_new :: IO (Ptr ())

foreign import ccall unsafe "verilambda_blinky_delete"
  c_blinky_delete :: Ptr () -> IO ()

foreign import ccall unsafe "verilambda_blinky_step"
  c_blinky_step :: Ptr () -> Ptr BlinkyState -> Ptr BlinkyState -> IO ()

foreign import ccall unsafe "verilambda_blinky_final"
  c_blinky_final :: Ptr () -> IO ()

foreign import ccall unsafe "verilambda_blinky_trace_open"
  c_blinky_trace_open :: Ptr () -> CString -> IO ()

foreign import ccall unsafe "verilambda_blinky_trace_close"
  c_blinky_trace_close :: Ptr () -> IO ()

foreign import ccall unsafe "verilambda_blinky_trace_dump"
  c_blinky_trace_dump :: Ptr () -> Word64 -> IO ()

-- * Port record

{- | HKD port record for Blinky. Shape must match the Clash manifest and
 the shim's @verilambda_blinky_state_t@ layout.
-}
data BlinkyPorts f = BlinkyPorts
  { clock_50 :: f Bit
  , key0 :: f Bit
  , ledr :: f (BitVector 8)
  }
  deriving stock (Generic)
  deriving anyclass (Ports)

-- * C-ABI state struct

{- | Mirror of @verilambda_blinky_state_t@. Storable layout must match
 the shim's struct definition exactly.
-}
data BlinkyState = BlinkyState
  { sClock50 :: !Word8
  , sKey0 :: !Word8
  , sLedr :: !Word8
  }
  deriving stock (Show, Eq)

instance Storable BlinkyState where
  sizeOf _ = 3
  alignment _ = 1
  peek p = do
    c <- peekByteOff p 0
    k <- peekByteOff p 1
    l <- peekByteOff p 2
    pure (BlinkyState c k l)
  poke p (BlinkyState c k l) = do
    pokeByteOff p 0 c
    pokeByteOff p 1 k
    pokeByteOff p 2 l

-- * SimBackend wiring

blinkyBackend :: SimBackend BlinkyPorts BlinkyState
blinkyBackend =
  SimBackend
    { sbNew = c_blinky_new
    , sbDelete = c_blinky_delete
    , sbStep = c_blinky_step
    , sbFinal = c_blinky_final
    , sbInitialState = BlinkyState 0 0 0
    , sbTraceOpen =
        Just
          ( \sim path ->
              withCString path (c_blinky_trace_open sim)
          )
    , sbTraceClose = Just c_blinky_trace_close
    , sbTraceDump = Just c_blinky_trace_dump
    }

-- * Testbench body

{- | Advance the simulation by one clock period — drive CLOCK_50 low,
 eval, then drive it high, eval. The rising edge on the second eval
 is what triggers all the synchronous logic inside the DUT.
-}
clockCycle :: SimM BlinkyPorts BlinkyState ()
clockCycle = do
  modifyState $ \s -> s {sClock50 = 0}
  tick
  modifyState $ \s -> s {sClock50 = 1}
  tick

main :: IO ()
main = do
  runSim blinkyBackend $ do
    -- Assert reset: KEY0 low for a few cycles, then release.
    pokeState (BlinkyState 0 0 0)
    _ <- clockCycle >> clockCycle >> clockCycle
    modifyState $ \s -> s {sKey0 = 1}

    -- Observe LEDR transitions through 10M cycles (~200 ms board time).
    liftIOPutStrLn "cycle          LEDR"
    liftIOPutStrLn "----------  --------"
    _ <- loop 0 0 10_000_000
    liftIOPutStrLn "(end)"
 where
  loop :: Int -> Word8 -> Int -> SimM BlinkyPorts BlinkyState Word8
  loop cyc last_ n
    | cyc >= n = pure last_
    | otherwise = do
        clockCycle
        s <- peekState
        let ledrNow = sLedr s
        when (ledrNow /= last_) $
          liftIOPutStrLn (formatRow cyc ledrNow)
        loop (cyc + 1) ledrNow n

-- * Helpers

liftIOPutStrLn :: String -> SimM ports state ()
liftIOPutStrLn = liftIO . putStrLn

formatRow :: Int -> Word8 -> String
formatRow cyc v =
  padLeft 10 (show cyc) <> "  " <> bin v
 where
  padLeft n s = replicate (n - length s) ' ' <> s
  bin w =
    [ if testBit w b then '1' else '0'
    | b <- [7, 6, 5, 4, 3, 2, 1, 0]
    ]
  testBit w b = (w `div` (2 ^ b)) `mod` 2 == 1

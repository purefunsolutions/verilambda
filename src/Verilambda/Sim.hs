-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | The 'SimM' monad: the runtime core of the verilambda eDSL.

'SimM' is concretely @ReaderT SimEnv IO@. A 'SimEnv' holds the opaque C
'Sim' pointer plus a 'SimBackend' record of function pointers that the
shim exposes. Downstream code — the Blinky example, the Setup.hs hook,
whatever — constructs a 'SimBackend' matching its DUT and runs a
'SimM' block via 'runSim'.

For v0.1 the backend is constructed manually per DUT by hand-writing
eight @foreign import ccall@ declarations (see the @blinky@ example).
@verilambda-shim-gen@ will emit these automatically once the Cabal
hook layer lands.
-}
module Verilambda.Sim (
  -- * The monad
  SimM,
  runSim,

  -- * Backend (DUT-specific FFI dictionary)
  Sim (..),
  SimBackend (..),

  -- * Primitive time / reset / state control
  tick,
  cycles,
  pokeState,
  peekState,
  modifyState,
)
where

import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Reader (ReaderT, ask, runReaderT)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Kind (Type)
import Data.Word (Word64)
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (Ptr)
import Foreign.Storable (Storable, peek, poke)

-- * Types

{- | Opaque handle to the C-side simulator. Users never touch the pointer
  directly; the library moves it through 'SimBackend' calls.
-}
newtype Sim (ports :: (Type -> Type) -> Type) = Sim {unSim :: Ptr ()}

{- | DUT-specific FFI dictionary. Every field is a pure IO action over
  the C 'Sim' handle and a @state@ struct matching the DUT's ports.
-}
data SimBackend ports state = SimBackend
  { sbNew :: IO (Ptr ())
  , sbDelete :: Ptr () -> IO ()
  , sbStep :: Ptr () -> Ptr state -> Ptr state -> IO ()
  , sbFinal :: Ptr () -> IO ()
  , sbInitialState :: state
  {- ^ Default value written into the model before the first step;
  typically all zeros.
  -}
  , sbTraceOpen :: Maybe (Ptr () -> FilePath -> IO ())
  , sbTraceClose :: Maybe (Ptr () -> IO ())
  , sbTraceDump :: Maybe (Ptr () -> Word64 -> IO ())
  }

-- | Internal environment threaded through the 'SimM' monad.
data SimEnv ports state = SimEnv
  { seSim :: Ptr ()
  , seBackend :: SimBackend ports state
  , seStateRef :: IORef state
  -- ^ The current view of the DUT's state — updated after every tick.
  , seTimeRef :: IORef Word64
  }

{- | The simulation monad. A concrete @ReaderT@ over 'IO'; the @ports@ and
  @state@ parameters carry the DUT shape but do not add runtime cost.
-}
newtype SimM (ports :: (Type -> Type) -> Type) state a = SimM
  { unSimM :: ReaderT (SimEnv ports state) IO a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO)

-- * Runner

{- | Run a 'SimM' block against a DUT backend. Creates a fresh sim,
threads it through the action, and tears it down deterministically
(including any VCD trace that was opened mid-run).
-}
runSim ::
  forall ports state a.
  SimBackend ports state ->
  SimM ports state a ->
  IO a
runSim backend (SimM action) = do
  simPtr <- sbNew backend
  stateRef <- newIORef (sbInitialState backend)
  timeRef <- newIORef 0
  let env = SimEnv simPtr backend stateRef timeRef
  result <- runReaderT action env
  mapM_ ($ simPtr) (sbTraceClose backend)
  sbFinal backend simPtr
  sbDelete backend simPtr
  pure result

-- * Time / state control

{- | Advance the simulation by exactly one clock period. Internally drives
  every input signal currently held in the shadow state struct into
  the model, calls @eval()@, dumps a VCD sample if tracing is open,
  and reads the post-eval state back.
-}
tick :: (Storable state) => SimM ports state ()
tick = SimM $ do
  SimEnv {..} <- ask
  let backend = seBackend
  liftIO $
    alloca $ \inPtr ->
      alloca $ \outPtr -> do
        s <- readIORef seStateRef
        poke inPtr s
        sbStep backend seSim inPtr outPtr
        s' <- peek outPtr
        writeIORef seStateRef s'
        t <- readIORef seTimeRef
        mapM_ (\f -> f seSim t) (sbTraceDump backend)
        writeIORef seTimeRef (t + 1)

-- | Advance the simulation by @n@ clock periods.
cycles :: (Storable state) => Int -> SimM ports state ()
cycles n | n <= 0 = pure ()
cycles n = tick >> cycles (n - 1)

{- | Replace the entire shadow state record. The new value is driven into
  the model's input fields on the next 'tick'.
-}
pokeState :: state -> SimM ports state ()
pokeState s = SimM $ do
  SimEnv {..} <- ask
  liftIO (writeIORef seStateRef s)

{- | Read the current shadow state — what the model showed on the last
  'tick', plus any writes the user has staged since.
-}
peekState :: SimM ports state state
peekState = SimM $ do
  SimEnv {..} <- ask
  liftIO (readIORef seStateRef)

{- | Modify the shadow state in place. Useful for writing a single input
  field without re-writing the whole record.
-}
modifyState :: (state -> state) -> SimM ports state ()
modifyState f = SimM $ do
  SimEnv {..} <- ask
  liftIO (modifyIORef' seStateRef f)

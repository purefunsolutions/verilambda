-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | Pure text templates for the C++ shim.

The shim exposes a narrow C ABI per DUT:

  * @verilambda_<top>_new@ / @verilambda_<top>_delete@  — lifecycle
  * @verilambda_<top>_step@                             — transfer state + eval
  * @verilambda_<top>_trace_*@                          — VCD plumbing

Signal transfer is atomic through a single packed struct of all the DUT's
ports. Inputs are written to the model before @eval()@; outputs (and the
echo of inputs) are read back afterwards. One foreign import on the
Haskell side handles every DUT — no per-port FFI code generation is
needed.
-}
module Verilambda.ShimGen.CppTemplate (
  renderShimHeader,
  renderShimSource,
  ShimGenInput (..),
) where

import Data.Text (Text)
import Data.Text qualified as Text
import Verilambda.Manifest (Port (..))
import Verilambda.Types (Direction (..))

-- | Everything the shim templates need from the manifest in one bundle.
data ShimGenInput = ShimGenInput
  { sgiTopName :: Text
  -- ^ Verilog top entity name (e.g. @blinky@).
  , sgiPorts :: [Port]
  -- ^ Flat port list in declaration order.
  }
  deriving stock (Eq, Show)

-- * Header

-- | Render the C-ABI header.
renderShimHeader :: ShimGenInput -> Text
renderShimHeader ShimGenInput {..} =
  Text.unlines $
    [ hdrCopyright
    , ""
    , "#ifndef VERILAMBDA_" <> upperTop <> "_SHIM_H"
    , "#define VERILAMBDA_" <> upperTop <> "_SHIM_H"
    , ""
    , "#include <stdint.h>"
    , ""
    , "#ifdef __cplusplus"
    , "extern \"C\" {"
    , "#endif"
    , ""
    , "typedef void* VerilambdaSim;"
    , ""
    , "/* Packed state of every port. Passed into step() with inputs filled"
    , " * in; step() overwrites it with the post-eval values of every port."
    , " * Fields are in declaration order; this must match the user's HKD"
    , " * record layout."
    , " */"
    , "typedef struct {"
    ]
      <> fmap portStructField sgiPorts
      <> [ "} verilambda_" <> lowerTop <> "_state_t;"
         , ""
         , "VerilambdaSim verilambda_" <> lowerTop <> "_new(void);"
         , "void verilambda_" <> lowerTop <> "_delete(VerilambdaSim sim);"
         , ""
         , "/* Copy in.inputs → model, eval, copy every port → out."
         , " * in and out may alias. */"
         , "void verilambda_" <> lowerTop <> "_step("
         , "    VerilambdaSim sim,"
         , "    const verilambda_" <> lowerTop <> "_state_t* in,"
         , "    verilambda_" <> lowerTop <> "_state_t* out);"
         , ""
         , "void verilambda_" <> lowerTop <> "_trace_open(VerilambdaSim sim, const char* path);"
         , "void verilambda_" <> lowerTop <> "_trace_close(VerilambdaSim sim);"
         , "void verilambda_" <> lowerTop <> "_trace_dump(VerilambdaSim sim, uint64_t time);"
         , ""
         , "void verilambda_" <> lowerTop <> "_final(VerilambdaSim sim);"
         , ""
         , "#ifdef __cplusplus"
         , "}"
         , "#endif"
         , "#endif"
         ]
 where
  lowerTop = Text.toLower sgiTopName
  upperTop = Text.toUpper sgiTopName

portStructField :: Port -> Text
portStructField p = "  " <> cTypeFor (portWidth p) <> " " <> portName p <> ";"

-- * Source

renderShimSource :: ShimGenInput -> Text
renderShimSource ShimGenInput {..} =
  Text.unlines $
    [ hdrCopyright
    , ""
    , "#include \"verilambda_" <> lowerTop <> "_shim.h\""
    , "#include \"V" <> sgiTopName <> ".h\""
    , "#include \"verilated.h\""
    , "#include \"verilated_vcd_c.h\""
    , ""
    , "namespace {"
    , ""
    , "struct Wrapper {"
    , "  VerilatedContext ctx;"
    , "  V" <> sgiTopName <> "* top;"
    , "  VerilatedVcdC* trace;"
    , "  uint64_t time;"
    , "  Wrapper() : top(new V" <> sgiTopName <> "(&ctx, \"TOP\")), trace(nullptr), time(0) {"
    , "    Verilated::traceEverOn(true);"
    , "  }"
    , "  ~Wrapper() {"
    , "    if (trace) { trace->close(); delete trace; }"
    , "    top->final();"
    , "    delete top;"
    , "  }"
    , "};"
    , ""
    , "}  // anon namespace"
    , ""
    , "extern \"C\" {"
    , ""
    , "VerilambdaSim verilambda_" <> lowerTop <> "_new(void) {"
    , "  return static_cast<VerilambdaSim>(new Wrapper());"
    , "}"
    , ""
    , "void verilambda_" <> lowerTop <> "_delete(VerilambdaSim sim) {"
    , "  delete static_cast<Wrapper*>(sim);"
    , "}"
    , ""
    , "void verilambda_" <> lowerTop <> "_step("
    , "    VerilambdaSim sim,"
    , "    const verilambda_" <> lowerTop <> "_state_t* in,"
    , "    verilambda_" <> lowerTop <> "_state_t* out) {"
    , "  auto* w = static_cast<Wrapper*>(sim);"
    ]
      <> fmap writeInputLine sgiPorts
      <> [ "  w->top->eval();"
         ]
      <> fmap readPortLine sgiPorts
      <> [ "}"
         , ""
         , "void verilambda_" <> lowerTop <> "_trace_open(VerilambdaSim sim, const char* path) {"
         , "  auto* w = static_cast<Wrapper*>(sim);"
         , "  if (w->trace) return;"
         , "  w->trace = new VerilatedVcdC;"
         , "  w->top->trace(w->trace, 99);"
         , "  w->trace->open(path);"
         , "}"
         , ""
         , "void verilambda_" <> lowerTop <> "_trace_close(VerilambdaSim sim) {"
         , "  auto* w = static_cast<Wrapper*>(sim);"
         , "  if (!w->trace) return;"
         , "  w->trace->close();"
         , "  delete w->trace;"
         , "  w->trace = nullptr;"
         , "}"
         , ""
         , "void verilambda_" <> lowerTop <> "_trace_dump(VerilambdaSim sim, uint64_t t) {"
         , "  auto* w = static_cast<Wrapper*>(sim);"
         , "  if (w->trace) { w->trace->dump(t); }"
         , "  w->time = t;"
         , "}"
         , ""
         , "void verilambda_" <> lowerTop <> "_final(VerilambdaSim sim) {"
         , "  static_cast<Wrapper*>(sim)->top->final();"
         , "}"
         , ""
         , "}  // extern \"C\""
         ]
 where
  lowerTop = Text.toLower sgiTopName

  writeInputLine :: Port -> Text
  writeInputLine p = case portDirection p of
    In -> "  w->top->" <> portName p <> " = in->" <> portName p <> ";"
    Out -> "  /* " <> portName p <> " is an output — not driven from in */"
    InOut -> "  /* " <> portName p <> " InOut not supported in v0.1 */"

  readPortLine :: Port -> Text
  readPortLine p = case portDirection p of
    InOut -> "  /* " <> portName p <> " InOut not supported in v0.1 */"
    _ -> "  out->" <> portName p <> " = w->top->" <> portName p <> ";"

-- * Shared helpers

hdrCopyright :: Text
hdrCopyright =
  Text.unlines
    [ "// AUTOMATICALLY GENERATED by verilambda-shim-gen. DO NOT EDIT."
    , "// Regenerate by re-running `cabal build` in the project that"
    , "// depends on verilambda."
    ]

{- | Map a port's bit-width to the smallest C integer type Verilator
 would pick for it. Matches Verilator's own IData/QData conventions.
-}
cTypeFor :: Int -> Text
cTypeFor w
  | w <= 8 = "uint8_t"
  | w <= 16 = "uint16_t"
  | w <= 32 = "uint32_t"
  | w <= 64 = "uint64_t"
  | otherwise =
      error $
        "verilambda: port widths > 64 bits not supported in v0.1 MVP "
          <> "(got "
          <> show w
          <> " bits)"

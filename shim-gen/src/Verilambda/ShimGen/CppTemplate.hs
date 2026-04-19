-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | Pure text templates for the C++ shim.

Keeping the templates in Haskell strings rather than Mustache / Shakespeare
means we pay the cost of a little manual escaping in exchange for:

  * no extra runtime dependency,
  * clear line-by-line reading of what the shim will emit,
  * easy golden-testing via @tasty-golden@.

The templates are parameterised by the DUT's top-module name and flat
port list (see 'Verilambda.Manifest.Port'). Direction determines whether
we emit a setter (In) or a getter (Out); InOut is flagged as an error in
the MVP.
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

{- | Render the C-ABI header that downstream tooling (our Haskell FFI
 module, user-written wrappers) consumes.
-}
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
    , "VerilambdaSim verilambda_" <> lowerTop <> "_new(void);"
    , "void verilambda_" <> lowerTop <> "_delete(VerilambdaSim sim);"
    , "void verilambda_" <> lowerTop <> "_eval(VerilambdaSim sim);"
    , "void verilambda_" <> lowerTop <> "_final(VerilambdaSim sim);"
    , ""
    ]
      <> fmap (headerPortAccessor lowerTop) sgiPorts
      <> [ ""
         , "void verilambda_" <> lowerTop <> "_trace_open(VerilambdaSim sim, const char* path);"
         , "void verilambda_" <> lowerTop <> "_trace_close(VerilambdaSim sim);"
         , "void verilambda_" <> lowerTop <> "_trace_dump(VerilambdaSim sim, uint64_t time);"
         , ""
         , "#ifdef __cplusplus"
         , "}"
         , "#endif"
         , "#endif"
         ]
 where
  lowerTop = Text.toLower sgiTopName
  upperTop = Text.toUpper sgiTopName

headerPortAccessor :: Text -> Port -> Text
headerPortAccessor top p =
  case portDirection p of
    In ->
      "void verilambda_"
        <> top
        <> "_set_"
        <> portName p
        <> "(VerilambdaSim sim, "
        <> cTypeFor (portWidth p)
        <> " value);"
    Out ->
      cTypeFor (portWidth p)
        <> " verilambda_"
        <> top
        <> "_get_"
        <> portName p
        <> "(VerilambdaSim sim);"
    InOut ->
      "/* INOUT port "
        <> portName p
        <> " not supported in verilambda v0.1 MVP */"

-- * Source

{- | Render the C++ source that wraps the Verilator-generated @V<top>@
 class behind the C ABI declared in the header.
-}
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
    , "void verilambda_" <> lowerTop <> "_eval(VerilambdaSim sim) {"
    , "  static_cast<Wrapper*>(sim)->top->eval();"
    , "}"
    , ""
    , "void verilambda_" <> lowerTop <> "_final(VerilambdaSim sim) {"
    , "  static_cast<Wrapper*>(sim)->top->final();"
    , "}"
    , ""
    ]
      <> concatMap (sourcePortAccessor lowerTop) sgiPorts
      <> [ ""
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
         , "  if (w->trace) w->trace->dump(t);"
         , "  w->time = t;"
         , "}"
         , ""
         , "}  // extern \"C\""
         ]
 where
  lowerTop = Text.toLower sgiTopName

sourcePortAccessor :: Text -> Port -> [Text]
sourcePortAccessor top p =
  case portDirection p of
    In ->
      [ "void verilambda_"
          <> top
          <> "_set_"
          <> portName p
          <> "(VerilambdaSim sim, "
          <> cTypeFor (portWidth p)
          <> " value) {"
      , "  static_cast<Wrapper*>(sim)->top->" <> portName p <> " = value;"
      , "}"
      , ""
      ]
    Out ->
      [ cTypeFor (portWidth p)
          <> " verilambda_"
          <> top
          <> "_get_"
          <> portName p
          <> "(VerilambdaSim sim) {"
      , "  return static_cast<Wrapper*>(sim)->top->" <> portName p <> ";"
      , "}"
      , ""
      ]
    InOut -> ["/* INOUT port " <> portName p <> " not supported */"]

-- * Shared helpers

hdrCopyright :: Text
hdrCopyright =
  Text.unlines
    [ "// AUTOMATICALLY GENERATED by verilambda-shim-gen. DO NOT EDIT."
    , "// Regenerate by re-running `cabal build` in the project that"
    , "// depends on verilambda."
    ]

{- | Map a port's bit-width to the smallest C integer type Verilator
 would pick for it. Matches Verilator's own conventions for
 @IData@/@QData@ selection.
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

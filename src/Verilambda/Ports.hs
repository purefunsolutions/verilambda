-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | Higher-kinded-data port records: how a user describes the shape of
a DUT's Verilog ports to verilambda.

The usual shape is:

@
data BlinkyPorts f = BlinkyPorts
  { clock_50 :: f Bit
  , key0     :: f Bit
  , ledr     :: f (BitVector 8)
  } deriving stock Generic
    deriving anyclass Ports
@

Deriving 'Ports' anyclass activates a Generics-based default
implementation of 'portSpec', which walks the record's 'Generic'
representation and produces a list of 'PortMeta' in declaration order.
That list is what the build-time shim generator and the runtime SimM
monad both consume.

Each field's type must have an 'IsPortType' instance; for v0.1 the
supported types are 'Bit' and 'BitVector n'. Expanding to 'Signed n' /
'Unsigned n' / 'Vec n a' / custom ADTs is tracked as v0.2 work in
PLAN.md.
-}
module Verilambda.Ports (
  -- * Main class
  Ports (..),
  PortMeta (..),

  -- * Port element types
  IsPortType (..),

  -- * Generic machinery (re-exported for user overrides)
  GPortList (..),
) where

import Clash.Sized.Internal.BitVector (BitVector)
import Data.Functor.Identity (Identity)
import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Generics (
  C1,
  D1,
  Generic (Rep),
  K1,
  S1,
  Selector (selName),
  U1,
  (:*:),
  (:+:),
 )
import GHC.TypeLits (KnownNat, natVal)
import Verilambda.Types (Bit)

{- | Metadata about one port: its name as the C/Verilog side sees it, and
its bit-width.

Direction is not tracked here; the Clash manifest is the authoritative
source for in vs. out classification. 'Ports' describes the record
shape; 'Verilambda.Manifest' describes the DUT.
-}
data PortMeta = PortMeta
  { pmName :: Text
  , pmWidth :: Int
  }
  deriving stock (Eq, Show)

{- | A record is a 'Ports' when its HKD fields can be walked by Generics
into a flat list of 'PortMeta'. The default implementation does this
automatically; override only if your record is not a single-constructor
product of named fields.
-}
class Ports (r :: (Type -> Type) -> Type) where
  portSpec :: Proxy r -> [PortMeta]
  default portSpec ::
    (GPortList (Rep (r Identity))) =>
    Proxy r ->
    [PortMeta]
  portSpec _ = gPortList @(Rep (r Identity))

{- | A Haskell type that can live on a port. Knows its bit-width so the
shim generator can emit the matching C integer field.
-}
class IsPortType a where
  portTypeWidth :: Proxy a -> Int

instance IsPortType Bit where
  portTypeWidth _ = 1

instance (KnownNat n) => IsPortType (BitVector n) where
  portTypeWidth _ = fromIntegral (natVal (Proxy @n))

-- HKD records are walked at type @Identity@, so we delegate through
-- Identity transparently. Users who instantiate their record at some other
-- functor for spec extraction aren't supported in the v0.1 MVP.
instance (IsPortType a) => IsPortType (Identity a) where
  portTypeWidth _ = portTypeWidth (Proxy @a)

-- * Generic walking

{- | Internal: walk a GHC.Generics representation, emitting a 'PortMeta'
for each record field.

Exposed for users who want to write custom 'Ports' instances for records
that aren't plain one-constructor products; the common case never needs
to touch this.
-}
class GPortList (rep :: Type -> Type) where
  gPortList :: [PortMeta]

instance (GPortList f) => GPortList (D1 d f) where
  gPortList = gPortList @f

instance (GPortList f) => GPortList (C1 c f) where
  gPortList = gPortList @f

instance (GPortList f, GPortList g) => GPortList (f :*: g) where
  gPortList = gPortList @f ++ gPortList @g

-- Each field becomes one PortMeta. We use the Selector meta to recover
-- the field name at runtime and IsPortType to recover its width.
instance
  (Selector s, IsPortType a) =>
  GPortList (S1 s (K1 r a))
  where
  gPortList =
    [ PortMeta
        { pmName = Text.pack (selName (undefined :: S1 s (K1 r a) p))
        , pmWidth = portTypeWidth (Proxy @a)
        }
    ]

-- The empty record and sum-type cases can't produce port records — they
-- exist only so GHC doesn't complain about orphan coverage.
instance GPortList U1 where
  gPortList = []

instance GPortList (f :+: g) where
  gPortList = error "Verilambda.Ports: port records must be single-constructor products, not sums"

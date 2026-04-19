-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT OR BSD-3-Clause

{- | Hspec-flavoured expectations for SimM testbenches.

These combinators let a testbench read like a spec:

@
cycles 4_194_304
peekState >>= (\\s -> ledr s \`shouldBe\` 1)
@

They are plain 'SimM' actions; no monad-stack trickery. A failure throws
'ExpectationFailure', which Tasty's test-tree will catch and present as
the failed assertion. In property-test contexts (Hedgehog / QuickCheck)
the same exception mechanism works.
-}
module Verilambda.Expectations (
  ExpectationFailure (..),
  shouldBe,
  shouldSatisfy,
  shouldNotBe,
  expectationFailure,
) where

import Control.Exception (Exception, throwIO)
import Control.Monad.IO.Class (MonadIO, liftIO)

-- | Thrown when a 'shouldBe' / 'shouldSatisfy' check fails.
data ExpectationFailure = ExpectationFailure
  { efMessage :: String
  }
  deriving stock (Show)

instance Exception ExpectationFailure

{- | Assert that an observed value equals an expected value. The
expected value is the second argument — mirroring @hspec@'s convention
of "subject `shouldBe` expected".
-}
shouldBe :: (MonadIO m, Eq a, Show a) => a -> a -> m ()
shouldBe actual expected
  | actual == expected = pure ()
  | otherwise =
      liftIO . throwIO . ExpectationFailure $
        "expected: "
          <> show expected
          <> "\n but got: "
          <> show actual

-- | Assert that an observed value does not equal an unwanted value.
shouldNotBe :: (MonadIO m, Eq a, Show a) => a -> a -> m ()
shouldNotBe actual unwanted
  | actual /= unwanted = pure ()
  | otherwise =
      liftIO . throwIO . ExpectationFailure $
        "expected not to equal: "
          <> show unwanted
          <> "\n but got: "
          <> show actual

{- | Assert that an observed value satisfies a predicate. The second
 argument is the predicate description, used in the error message.
-}
shouldSatisfy :: (MonadIO m, Show a) => a -> (a -> Bool) -> m ()
shouldSatisfy actual predicate
  | predicate actual = pure ()
  | otherwise =
      liftIO . throwIO . ExpectationFailure $
        "value did not satisfy predicate: " <> show actual

{- | Unconditionally fail an expectation. Useful for flagging unreachable
 testbench branches ("this clock edge should never occur").
-}
expectationFailure :: (MonadIO m) => String -> m ()
expectationFailure msg = liftIO . throwIO $ ExpectationFailure msg

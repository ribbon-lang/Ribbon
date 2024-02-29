module Language.Ribbon.Util where

import Data.Foldable

import Control.Applicative
import Control.Monad.Except

import Data.List qualified as List
import Data.Maybe qualified as Maybe
import Data.Either qualified as Either

import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as ByteString

import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text

import Text.Pretty




-- | Marks something not yet implemented
todo :: a
todo = error "TODO"

-- | Drop elements from the end of a list
dropTail :: Int -> [a] -> [a]
dropTail n = reverse . drop n . reverse

-- | ByteString -> String
bytesToString :: ByteString -> String
bytesToString
    = Text.unpack
    . Text.decodeUtf8
    . ByteString.toStrict

-- | Branch on a boolean, selecting a or b for true or false, respectively
select :: Bool -> a -> a -> a
select True a _ = a
select False _ b = b

-- | Branch on a boolean, selecting a or b for true or false, respectively
selecting :: a -> a -> Bool -> a
selecting a b p = select p a b

-- | equivalent of Applicative.some (one or more) with unit return value
some_ :: Alternative f => f a -> f ()
some_ a = some_v where
    many_v = option () some_v
    some_v = a *> many_v

-- | equivalent of Applicative.many (zero or more) with unit return value
many_ :: Alternative f => f a -> f ()
many_ a = many_v where
    many_v = option () some_v
    some_v = a *> many_v

-- | equivalent of Applicative.many (zero or more) with indexing
manyN :: (Num n, Alternative f) => (n -> f a) -> f [a]
manyN f = many_v 0 where
    many_v n = option [] (liftA2 (:) (f n) (many_v (n + 1)))

-- | equivalent of Applicative.some (one or more) with indexing
someN :: (Num n, Alternative f) => (n -> f a) -> f [a]
someN f = liftA2 (:) (f 0) (many_v 1) where
    many_v n = option [] (liftA2 (:) (f n) (many_v (n + 1)))

-- | equivalent of Applicative.some (one or more) with base value
someWith :: Alternative f => [a] -> f a -> f [a]
someWith base a = some_v where
    many_v = option base some_v
    some_v = liftA2 (:) a many_v

-- | equivalent of Applicative.many (zero or more) with base value
manyWith :: Alternative f => [a] -> f a -> f [a]
manyWith base a = many_v where
    many_v = option base some_v
    some_v = liftA2 (:) a many_v

-- | @optional@, with a default
option :: Alternative f => a -> f a -> f a
option a fa = fa <|> pure a

-- | The reverse of @(.)@
compose :: (a -> b) -> (b -> c) -> (a -> c)
compose f g a = g (f a)

-- | Compose a list of functions
composeAll :: [a -> a] -> a -> a
composeAll = foldr compose id

-- | Compose a binary function
(.:) :: (c -> d) -> (a -> b -> c) -> a -> b -> d
(.:) = (.) . (.)

-- | The reverse of @(.:)@
compose2 :: (a -> b -> c) -> (c -> d) -> a -> b -> d
compose2 = flip (.:)

-- | Split a list into multiple sub-lists
--   at each element that satisfies a predicate
splitWith :: (a -> Bool) -> [a] -> [[a]]
splitWith p = go where
    go [] = []
    go xs = case break p xs of
        (a, _ : b) -> a : go b
        _ -> [xs]

-- | Split a list into multiple sub-lists
--   at each element that is equal to a given value
splitOn :: Eq a => a -> [a] -> [[a]]
splitOn = splitWith . (==)

-- | Compositional @&&@
(&&&) :: (a -> Bool) -> (a -> Bool) -> (a -> Bool)
(&&&) f g a = f a && g a
infixl 8 &&&

-- | Compositional @||@
(|||) :: (a -> Bool) -> (a -> Bool) -> (a -> Bool)
(|||) f g a = f a || g a
infixl 8 |||

-- | Compositional @not@
not'd :: (a -> Bool) -> (a -> Bool)
not'd f a = not (f a)

-- | The reverse of (>>)
(<<) :: Monad m => m b -> m a -> m b
(<<) ma mb = do a <- ma; a <$ mb

-- | `show s` without the quotes
escapeString :: String -> String
escapeString = init . tail . show

-- | `show c` without the quotes
escapeChar :: Char -> String
escapeChar = escapeString . pure

-- | Maybe -> Monad with monadic failure case
liftMaybe :: Monad m => m a -> Maybe a -> m a
liftMaybe failed = Maybe.maybe failed pure

-- | Maybe -> Monad with MonadFail string case
maybeFail :: MonadFail m => String -> Maybe a -> m a
maybeFail msg = liftMaybe (fail msg)

-- | Maybe -> Monad with MonadError error case
maybeError :: MonadError e m => e -> Maybe a -> m a
maybeError e = liftMaybe (throwError e)

-- | Maybe -> Alternative with empty case
maybeEmpty :: Alternative m => Maybe a -> m a
maybeEmpty = Maybe.maybe empty pure

-- | Maybe -> Monoid with mempty case
maybeMEmpty :: Monoid a => Maybe a -> a
maybeMEmpty = Maybe.fromMaybe mempty

-- | Either -> Left with exception on Right
forceLeft :: Either a b -> a
forceLeft = Either.fromLeft (error "expected left")

-- | Either -> Right with exception on Left
forceRight :: Either a b -> b
forceRight = Either.fromRight (error "expected right")

-- | Lift a 4 argument function into an Applicative
liftA4 :: Applicative m =>
    (a -> b -> c -> d -> e) -> m a -> m b -> m c -> m d -> m e
liftA4 f ma mb mc md = liftA3 f ma mb mc <*> md

-- | Fail with an expectation message if the condition is false
guardFail :: MonadFail m => Bool -> String -> m ()
guardFail p expStr = if p then pure () else fail expStr

-- | `foldr` with the function taken last
foldWith :: Foldable t => b -> t a -> (a -> b -> b) -> b
foldWith b as f = foldr f b as

-- | `foldr` with the function taken second
foldWith' :: Foldable t => b -> (a -> b -> b) -> t a -> b
foldWith' = flip foldr

-- | `foldrM` with the function taken last
foldWithM :: (Foldable t, Monad m) => b -> t a -> (a -> b -> m b) -> m b
foldWithM b as f = foldrM f b as

-- | `foldrM` with the function taken second
foldWithM' :: (Foldable t, Monad m) => b -> (a -> b -> m b) -> t a -> m b
foldWithM' = flip foldrM

-- | Force a string literal to be a @String@ under @OverloadedStrings@
pattern String :: String -> String
pattern String s = s

-- | Force a string literal to be a @Doc@ under @OverloadedStrings@
pattern Doc :: Doc -> Doc
pattern Doc s = s

-- | Utility class for the (</>) slash-connection concatenation operator
class SlashConnect a where
    -- | Concatenate with a slash between the elements
    (</>) :: a -> a -> a
    infixr 6 </>


instance SlashConnect String where
    (</>) a b
        | "/" `List.isSuffixOf` a || "/" `List.isPrefixOf` b = a <> b
        | otherwise = a <> "/" <> b

instance SlashConnect Doc where
    (</>) a b = a <> "/" <> b

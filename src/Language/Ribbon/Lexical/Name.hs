module Language.Ribbon.Lexical.Name where

import Data.Char qualified as Char

import Data.Sequence (Seq)
import Data.Sequence qualified as Seq

import Data.Foldable qualified as Fold

import Data.Nil

import Text.Pretty

import Language.Ribbon.Lexical.Fixity




-- | Class for name-likes to test if they need escaping with backticks
class NeedsEscape a where
    -- | Test if a name needs escaping with backticks
    needsEscape :: a -> Bool



-- | A variable name, without qualification.
--   Either a symbol or an identifier; never a reserved character sequence,
--   never a @FixName@, ie containing spaces indicating operator semantics
newtype SimpleName
    = SimpleName
    { value :: String }
    deriving (Eq, Ord, Show)

instance Pretty SimpleName where
    pPrint (SimpleName n) = text n

instance NeedsEscape SimpleName where
    needsEscape (SimpleName n) = not $ all Char.isAlphaNum n


-- | A variable name with operator semantics;
--   contains components that are either names or operand placeholders;
--   Note that @components@ should never be empty; however, it is not enforced
--   with @NonEmpty@ because a single operand with no names isn't valid either.
--   Additionally, it is not type-enforced that multiple operands are not
--   adjacent, but this is an invalid construction as well
newtype FixName
     = FixName
     { components :: Seq FixNameComponent }
    deriving (Eq, Ord, Show)

instance Pretty FixName where
    pPrint fn@(FixName cs) = maybeBackticks (needsEscape fn) $
        hcat $ pPrint <$> Fold.toList cs

instance NeedsEscape FixName where
    needsEscape (FixName cs) = any needsEscape cs

instance HasFixity FixName where
    getFixity (FixName Nil) = error "getFixity: FixName with no components"
    getFixity (FixName s@(h Seq.:<| _))
        | FixSimple _ <- h = case s of
            _ Seq.:|> q
                | FixSimple _ <- q -> Atom
                | FixOperand <- q -> Prefix
        | FixOperand <- h = case s of
            _ Seq.:|> q
                | FixSimple _ <- q -> Postfix
                | FixOperand <- q -> Infix

-- | Pattern alias for a @FixName@ with a single @SimpleName@
pattern SimpleFixName :: SimpleName -> FixName
pattern SimpleFixName n = FixName (FixSimple n Seq.:<| Nil)
{-# COMPLETE SimpleFixName #-}

data FixNameError
    = FixNameMissingSimple
    | FixNameAdjacentOperands
    deriving (Eq, Ord, Show)

instance Pretty FixNameError where
    pPrint = \case
        FixNameMissingSimple ->
            "fix name must contain at least one identifier or operator"
        FixNameAdjacentOperands ->
            "fix name must not contain adjacent operands"

validateFixName :: FixName -> Maybe FixNameError
validateFixName (FixName cs) = do
    if not $ any isFixSimple cs
        then Just FixNameMissingSimple
        else checkAdjacencies cs where
    checkAdjacencies Nil = Nothing
    checkAdjacencies (l Seq.:<| r)
        | FixOperand <- l, FixOperand Seq.:<| _ <- r =
            Just FixNameAdjacentOperands
        | otherwise = checkAdjacencies r

-- | A component of a variable name with operator semantics;
--   see @FixName@ for usage details
data FixNameComponent
    -- | A simple name (symbol or identifier), ie the + in \` + \`
    = FixSimple !SimpleName
    -- | An operand placeholder, ie the spaces in \` + \`
    | FixOperand
    deriving (Eq, Ord, Show)

instance Pretty FixNameComponent where
    pPrint = \case
        FixSimple n -> pPrint n
        FixOperand -> " "

instance NeedsEscape FixNameComponent where
    needsEscape = \case
        FixSimple n -> needsEscape n
        FixOperand -> True

isFixSimple :: FixNameComponent -> Bool
isFixSimple = \case
    FixSimple _ -> True
    _ -> False

isFixOperand :: FixNameComponent -> Bool
isFixOperand = \case
    FixOperand -> True
    _ -> False

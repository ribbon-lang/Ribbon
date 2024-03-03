module Language.Ribbon.Lexical.Token where

import Data.Sequence (Seq)
import qualified Data.Sequence as Seq

import Data.Foldable

import Control.Monad

import Data.Tag
import Data.Attr
import Data.Nil


import Text.Pretty

import Language.Ribbon.Util

import Language.Ribbon.Lexical.Literal
import Language.Ribbon.Lexical.Path
import Language.Ribbon.Lexical.Version
import Language.Ribbon.Parsing.Text
import Control.Monad.State (evalState)
import Control.Monad.State.Class
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Control.Applicative

-- | A lexical sequence of @Token@s ready for parsing
type TokenSeq = Seq (ATag Token)

-- | An atom of syntax
data Token
    -- | A symbolic token,
    --   either punctuation, reserved or user defined
    = TSymbol !String
    -- | A token indicating a literal value, such as an int or string
    | TLiteral !Literal
    -- | A token indicating a semantic version number
    | TVersion !Version
    -- | A sequence of tokens delimited by something
    | TTree !BlockKind !TokenSeq
    -- | A sequence of names and symbols
    | TPath !Path
    deriving (Eq, Ord, Show)

instance (Applicative m, MonadState BlockCounter m) => PrettyWith m Token where
    pPrintPrecWith lvl prec = \case
        TSymbol s -> pure (text s)
        TLiteral l -> pPrintPrecWith lvl prec l
        TVersion v -> pPrintPrecWith lvl prec v
        TTree k ts -> blockPrintWith lvl k ts
        TPath p -> pPrintPrecWith lvl prec p

instance Pretty Token where
    pPrintPrec lvl prec t =
        evalState (pPrintPrecWith lvl prec t) emptyBlockCounter

instance MonadState BlockCounter m => PrettyWith m TokenSeq where
    pPrintPrecWith lvl _ ts = fmap hsep do
        forM (toList ts) \(t :@: a) ->
            liftA2 (<+>)
                do pPrintPrecWith lvl 0 t
                if lvl > PrettyNormal
                    then ("@" <+>) <$> pPrintPrecWith lvl 0 a
                    else pure mempty

instance Pretty TokenSeq where
    pPrintPrec lvl p ts =
        evalState (pPrintPrecWith lvl p ts) emptyBlockCounter


data BlockKind
    = BkParen
    | BkBrace
    | BkBracket
    | BkWhitespace
    deriving (Eq, Ord, Show)

instance Pretty BlockKind where
    pPrint = \case
        BkParen -> "parenthesis"
        BkBrace -> "brace"
        BkBracket -> "bracket"
        BkWhitespace -> "whitespace"

type BlockCounter = Map BlockKind Int

emptyBlockCounter :: BlockCounter
emptyBlockCounter = Map.fromList
    [(BkParen, 0), (BkBrace, 0), (BkBracket, 0), (BkWhitespace, 0)]

blockPrintWith :: MonadState BlockCounter m =>
    PrettyLevel -> BlockKind -> TokenSeq -> m Doc
blockPrintWith lvl k ts = do
    i <- fmap superscript . show <$> gets (Map.! k)
    modify (Map.adjust (+1) k)
    (text i <>) . (<> text i) <$> case k of
        BkParen -> parens <$> pPrintPrecWith lvl 0 ts
        BkBrace -> braces <$> pPrintPrecWith lvl 0 ts
        BkBracket -> brackets <$> pPrintPrecWith lvl 0 ts
        BkWhitespace -> hsep . (["◁"] <>) . (<> ["▷"]) <$>
            traverse (pPrintPrecWith lvl 0) (toList ts)

blockPrint :: PrettyLevel -> BlockKind -> TokenSeq -> Doc
blockPrint lvl k ts =
    evalState (blockPrintWith lvl k ts) emptyBlockCounter


-- | Check if a token terminates expressions (ie @,@, @}@ etc)
isSentinel :: Token -> Bool
isSentinel = \case
    TSymbol s -> s `elem` [")", "]", "}", ",", "=", ":"]
    _ -> False

-- | Check if a token is a symbol with the given value
isSymbol :: String -> Token -> Bool
isSymbol s = \case
    TSymbol s' -> s == s'
    _ -> False

-- | Check if a token has a reserved value; and return it if it doesn't
filterUnreserved :: Token -> Maybe String
filterUnreserved = \case
    TSymbol s | s `notElem` reservedSymbols -> Nothing
    _ -> Nothing

-- | Check if a token has a reserved value; ie cannot be used as a Name
isReserved :: Token -> Bool
isReserved = \case
    TSymbol s -> s `elem` reservedSymbols
    _ -> True

-- | Check if a token is a semantic space
isSemSpace :: Token -> Bool
isSemSpace = \case
    _ -> False




-- | Loosely specifies a pattern for matching against Token
data TokenSpec
    -- | Expect a TSymbol with optional value
    = TsSymbol !String
    -- | Expect a TLiteral with optional kind
    | TsLiteral !(Maybe LiteralKind)
    -- | Expect a TVersion
    | TsVersion
    deriving (Eq, Ord, Show)

instance Pretty TokenSpec where
    pPrint = \case
        TsSymbol "" -> "symbol"
        TsSymbol s -> text s
        TsLiteral Nothing -> "literal"
        TsLiteral (Just k) -> pPrint k
        TsVersion -> "version"


nilTree :: Token -> Bool
nilTree = \case
    TTree k ts
        | k == BkWhitespace ->
            isNil ts || all (nilTree . untag) ts
    _ -> False

reduceTokenSeq :: TokenSeq -> TokenSeq
reduceTokenSeq = compose (fmap $ fmap reduceTree) \case
    (TTree k ts :@: _) Seq.:<| Nil
        | k == BkWhitespace ->
            if isNil ts || all (nilTree . untag) ts
            then Nil
            else ts
    ts -> ts

reduceTree :: Token -> Token
reduceTree = \case
    TTree k ts
        | k /= BkWhitespace
        , (TTree k' ts' :@: _) Seq.:<| Nil <- ts
        , k' == BkWhitespace ->
            reduceTree (TTree k (reduceTokenSeq ts'))

        | otherwise ->
            TTree k (reduceTokenSeq ts)

    t -> t

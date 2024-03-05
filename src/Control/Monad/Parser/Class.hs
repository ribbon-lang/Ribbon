module Control.Monad.Parser.Class where

import Data.Foldable
import Data.Functor

import Data.Tag
import Data.Attr
import Data.Nil
import Data.SyntaxError

import Control.Applicative
import Control.Monad.Except
import Control.Monad.Reader
import Control.Monad.State.Strict
import Control.Monad.State.Lazy qualified as Lazy

import Control.Monad.File

import Text.Pretty

import Language.Ribbon.Util



-- | The class of types that can be used as input for a @ParserT@
class (Eq (InputElement s), Pretty (InputElement s), Nil s)
    => ParseInput s where
        -- | The elements of a @ParseInput@, ie @Token@ for @TokenSeq@
        type InputElement s
        -- | Create a tagged @SyntaxFail@ for the given input and @FilePath@,
        --   either an eof or an unexpected character
        formatInput :: FilePath -> s -> ATag SyntaxFail
        -- | Get the next element of the input, or a @DecodeProblem@
        unconsInput :: s -> Either DecodeProblem (InputElement s, s)
        -- | Get the @Attr@ for the current input element,
        --   or for the input itself at eof
        attrInput :: FilePath -> s -> Attr
        -- | Get the @Attr@ for the range between two @ParseInput@s
        attrInputDiff :: FilePath -> s -> s -> Attr


-- | @MonadError SyntaxError@ + @MonadFail@
type MonadSyntaxError m = (MonadError SyntaxError m, MonadFail m)

-- | The class of monads that can be used as a parser,
--   see @ParserT@ for the base transformer, see @ParseInput@ for valid inputs
class ( Alternative m, MonadPlus m
      , MonadSyntaxError m, MonadFile m
      , ParseInput x
      )
    => MonadParse x m | m -> x where
        -- | Read/Write/Modify the @ParseInput@
        --   associated with the current parser action
        parseState :: (x -> (a, x)) -> m a

instance MonadParse x m => MonadParse x (StateT s m) where
    parseState = lift . parseState

instance MonadParse x m => MonadParse x (Lazy.StateT s m) where
    parseState = lift . parseState

instance MonadParse x m => MonadParse x (ReaderT r m) where
    parseState = lift . parseState

instance MonadParse i m => MonadParse i (FileT m) where
    parseState = lift . parseState




-- | Take the current @ParseInput@ state, and replace it with @Nil@
takeParseState :: MonadParse x m => m x
takeParseState = parseState (, Nil)

-- | Get a copy of the current @ParseInput@ state
getParseState :: MonadParse x m => m x
getParseState = parseState \ts -> (ts, ts)

-- | Replace the current @ParseInput@ state with the given one
putParseState :: MonadParse x m => x -> m ()
putParseState ts = parseState $ const ((), ts)

-- | Modify the current @ParseInput@ state with a map function
modifyParseState :: MonadParse x m => (x -> x) -> m ()
modifyParseState f = parseState \ts -> ((), f ts)




-- | Evaluate a parser on a new input.
--   The parser must consume all of the new input, or fail
recurseParser :: MonadParse x m => m a -> x -> m a
recurseParser px toks = do
    ts <- parseState (, toks)
    a <- consumesAll px `catchError` \e -> do
        putParseState ts
        throwError e
    a <$ putParseState ts


-- | Run a parser, and if it fails, make the @SyntaxError@ unrecoverable
noFail :: MonadParse x m => m a -> m a
noFail m = m `catchError` \(SyntaxError _ f) ->
    throwError $ SyntaxError Unrecoverable f

-- | Run a parser, and if it fails, make the @SyntaxError@ unrecoverable
--   when the given condition is @True@
noFailIf :: MonadParse x m => Bool -> m a -> m a
noFailIf p m = if p then noFail m else m

-- | Ensure that the given parser action consumes the remaining input
consumesAll :: MonadParse x m => m a -> m a
consumesAll m = do
    a <- m
    ts <- getParseState
    if isNil ts
        then pure a
        else do
            fp <- getFilePath
            throwError $ SyntaxError Recoverable $ formatInput fp ts


-- | Trigger an unrecoverable @SyntaxError@
--   with a message at the current location
parseError :: MonadParse x m => Recoverability -> Doc -> m a
parseError r msg = attr >>= \at -> parseErrorAt at r msg

-- | Trigger an unrecoverable @SyntaxError@
--   with a message at the given @Attr@
parseErrorAt :: MonadParse x m => Attr -> Recoverability -> Doc -> m a
parseErrorAt x r msg =
    throwError $ SyntaxError r $ SingleFailure msg :@: x


-- | Trigger an unrecoverable @SyntaxError@
--   with a message at the current location,
--   if the given condition is false
assert :: MonadParse x m => Bool -> Recoverability -> Doc -> m ()
assert p r expStr = unless p (parseError r expStr)

-- | Trigger an unrecoverable @SyntaxError@
--   with a message at the given @Attr@,
--   if the condition is false
assertAt :: MonadParse x m => Attr -> Bool -> Recoverability -> Doc -> m ()
assertAt x p r expStr = unless p (parseErrorAt x r expStr)




-- | Advance the @ParseInput@ in the current parser action
advance :: MonadParse x m => m ()
advance = do
    ps <- getParseState
    case unconsInput ps of
        Left e -> do
            fp <- getFilePath
            throwError $ SyntaxError Recoverable $
                formatProblem (attrInput fp ps) e
        Right (_, ps') -> putParseState ps'


-- | Get the currently selected @InputElement@ in the parser action
peek :: MonadParse x m => m (InputElement x)
peek = do
    ps <- getParseState
    case unconsInput ps of
        Left e -> do
            fp <- getFilePath
            throwError $ SyntaxError Recoverable $
                formatProblem (attrInput fp ps) e
        Right (t, _) -> pure t

-- | Get the currently selected @InputElement@ in the parser action,
--   returning @Nothing@ if the input is @Nil@
tryPeek :: MonadParse x m => m (Maybe (InputElement x))
tryPeek = do
    ps <- getParseState
    pure $ case unconsInput ps of
        Left _ -> Nothing
        Right (t, _) -> Just t

-- | Get a location @Attr@ for the selected position in the parser action
attr :: MonadParse x m => m Attr
attr = liftA2 attrInput getFilePath getParseState



-- | Wraps the output of a parser in an @ATag@ for the range consumed
tag :: MonadParse x m => m a -> m (ATag a)
tag p = do
    ps <- getParseState
    a <- p
    fp <- getFilePath
    ps' <- getParseState
    pure $ a :@: attrInputDiff fp ps ps'

-- | Execute @tag@ and discard the result, keeping only the @Attr@ generated
attrOf :: MonadParse x m => m a -> m Attr
attrOf = fmap tagOf . tag


-- | Get the currently selected @InputElement@ in the parser action,
--   and advance the stream offset
next :: MonadParse x m => m (InputElement x)
next = peek << advance

-- | Get the currently selected @InputElement@'s @Attr@ in the parser action
peekAttr :: MonadParse x m => m (ATag (InputElement x))
peekAttr = peek <*@*> attr

-- | Get the currently selected @InputElement@'s @Attr@ in the parser action,
--   and wrap it around the current @InputElement@ using @Tag@,
--   then advance the stream offset
nextAttr :: MonadParse x m => m (ATag (InputElement x))
nextAttr = tag next

-- | Advance the parser stream offset,
--   if the current @InputElement@ satisfies the predicate;
--   returning the matched @InputElement@
nextIf :: MonadParse x m => (InputElement x -> Bool) -> m (InputElement x)
nextIf p = do
    a <- peek
    if p a
        then a <$ advance
        else empty

-- | Advance the parser stream offset,
--   if the current @InputElement@ satisfies the predicate;
--   returning the matched @InputElement@ along with its @Attr@
nextIfAttr :: MonadParse x m =>
    (ATag (InputElement x) -> Bool) -> m (ATag (InputElement x))
nextIfAttr p = do
    t <- peekAttr
    if p t
        then t <$ advance
        else empty

-- | Advance the parser stream offset,
--   if the current @InputElement@ satisfies the predicate;
--   discarding the matched @InputElement@
nextIf_ :: MonadParse x m => (InputElement x -> Bool) -> m ()
nextIf_ p = do
    a <- peek
    if p a
        then advance
        else empty

-- | Advance the parser stream offset,
--   as long as the current @InputElement@ satisfies the predicate;
--   returning the matched @InputElement@s as a list
nextWhile :: MonadParse x m => (InputElement x -> Bool) -> m [InputElement x]
nextWhile p = some (nextIf p)

-- | Advance the parser stream offset,
--   as long as the current @InputElement@ satisfies the predicate;
--   returning the matched @InputElement@s as a list
nextWhileAttr :: MonadParse x m =>
    (ATag (InputElement x) -> Bool) -> m [ATag (InputElement x)]
nextWhileAttr p = some (nextIfAttr p)

-- | Advance the parser stream offset,
--   as long as the current @InputElement@ satisfies the predicate;
--   discarding the matched @InputElement@s
nextWhile_ :: MonadParse x m => (InputElement x -> Bool) -> m ()
nextWhile_ p = some_ (nextIf_ p)

-- | Advance the parser stream offset,
--   if the current @InputElement@ satisfies a mapping predicate;
--   returning the mapped value
nextMap :: MonadParse x m => (InputElement x -> Maybe a) -> m a
nextMap p = do
    a <- peek
    case p a of
        Just a' -> a' <$ advance
        _ -> empty


-- | Wrap the @SyntaxError@s of a given parser
--   in an explanation of the expectation that was had of it
expecting :: MonadParse x m => Doc -> m a -> m a
expecting msg px = px `catchError` \(SyntaxError r f) -> do
    fp <- getFilePath
    ts <- getParseState
    throwError $ SyntaxError r $ ExpectationFailure [msg] f :@: attrInput fp ts

-- | Wrap the @SyntaxError@s of a given parser
--   in an explanation of the expectations that were had of it
expectingMulti :: MonadParse x m => [Doc] -> m a -> m a
expectingMulti = expecting . lsep


-- | Wrap the @SyntaxError@s of a given parser
--   in an explanation of the expectation that was had of it
expectingAt :: MonadParse x m => Attr -> Doc -> m a -> m a
expectingAt at msg px = px `catchError` \(SyntaxError r f) ->
    throwError $ SyntaxError r $ ExpectationFailure [msg] f :@: at

-- | Wrap the @SyntaxError@s of a given parser
--   in an explanation of the expectations that were had of it
expectingMultiAt :: MonadParse x m => Attr -> [Doc] -> m a -> m a
expectingMultiAt at = expectingAt at . lsep


-- | @nextIf_ (== e)@
expect' :: MonadParse x m => InputElement x -> m ()
expect' e = nextIf_ (== e)

-- | @nextIf (`elem` es)@
expectAny' :: MonadParse x m => [InputElement x] -> m (InputElement x)
expectAny' es = nextIf (`elem` es)

-- | Consume an expected sequence of inputs
expectSeq' :: MonadParse x m => [InputElement x] -> m ()
expectSeq' = traverse_ \e -> do
    a <- peek
    if a == e
        then advance
        else empty

-- | Consume one of any expected sequences of inputs
expectAnySeq' :: MonadParse x m => [[InputElement x]] -> m [InputElement x]
expectAnySeq' es = do
    asum (es <&> \e -> e <$ expectSeq' e)


-- | @expecting (pPrint e) (expect' e)@
expect :: MonadParse x m => InputElement x -> m ()
expect e = expecting (pPrint e) (expect' e)

-- | @expectingMulti (pPrint <$> es) (expectAny' es)@
expectAny :: MonadParse x m => [InputElement x] -> m (InputElement x)
expectAny es = expectingMulti (pPrint <$> es) (expectAny' es)

-- | @expecting (pPrint e) (expectSeq' e)@
expectSeq :: MonadParse x m => [InputElement x] -> m ()
expectSeq e = expecting (pPrint e) (expectSeq' e)

-- | @expectingMulti (pPrint <$> es) (expectAnySeq' es)@
expectAnySeq :: MonadParse x m => [[InputElement x]] -> m [InputElement x]
expectAnySeq es = expectingMulti (pPrint <$> es) (expectAnySeq' es)


-- | Run a parser without consuming input
lookahead :: MonadParse x m => m a -> m a
lookahead p = do
    ps <- getParseState
    a <- p
    a <$ putParseState ps

-- | Run a parser without consuming input,
--   and fail if it succeeds
negativeLookahead :: MonadParse x m => m a -> m ()
negativeLookahead p = do
    ps <- getParseState
    ok <- (False <$ p) `catchError` \_ -> True <$ putParseState ps
    unless ok do
        fp <- getFilePath
        throwError $ SyntaxError Recoverable $ formatInput fp ps


-- | Ensure the output of a parser comes from a range connected to the given one
connected :: MonadParse x m => Attr -> m a -> m a
connected at lx = do
    x :@: at' <- tag lx
    x <$ assertAt at' (attrConnected at at') Recoverable do
        "expected an element connected to the previous"

-- | Ensure each successive output of a parser comes
--   from a range connected to the previous one, starting with the given one.
--   Equivalent to `some` (ie one or more results is required)
connectSome :: MonadParse x m => Attr -> m a -> m [a]
connectSome at lx = do
    a :@: at' <- tag (connected at lx)
    (a :) <$> connectMany at' lx

-- | Ensure each successive output of a parser comes
--   from a range connected to the previous one, starting with the given one.
--   Equivalent to `many` (ie zero or more results are allowed)
connectMany :: MonadParse x m => Attr -> m a -> m [a]
connectMany at lx = option [] (connectSome at lx)
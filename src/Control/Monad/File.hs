module Control.Monad.File where

import Control.Applicative
import Control.Monad.Trans

import Control.Monad.Reader
import Control.Monad.State.Strict qualified as Strict
import Control.Monad.State.Lazy qualified as Lazy
import Control.Monad.State.Class
import Control.Monad.Except


newtype FileT m a
    = FileT
    ( ReaderT FilePath m a )
    deriving
    ( Functor, Applicative, Monad, Alternative
    , MonadPlus, MonadFail, MonadTrans
    )

instance MonadReader r m => MonadReader r (FileT m) where
    ask = lift ask
    local f (FileT (ReaderT m)) = FileT (ReaderT (local f . m))
    reader = lift . reader

instance MonadState s m => MonadState s (FileT m) where
    get = lift get
    put = lift . put
    state = lift . state

runFileT :: FileT m a -> FilePath -> m a
runFileT (FileT m) = runReaderT m

class Monad m => MonadFile m where
    withFilePath :: FilePath -> m a -> m a
    getFilePath :: m FilePath

instance Monad m => MonadFile (FileT m) where
    withFilePath f (FileT m) = FileT $ ReaderT \_ -> runReaderT m f
    getFilePath = FileT (ReaderT pure)

instance MonadFile m => MonadFile (Strict.StateT s m) where
    withFilePath fp (Strict.StateT m) = Strict.StateT (withFilePath fp . m)
    getFilePath = lift getFilePath

instance MonadFile m => MonadFile (Lazy.StateT s m) where
    withFilePath fp (Lazy.StateT m) = Lazy.StateT (withFilePath fp . m)
    getFilePath = lift getFilePath

instance MonadFile m => MonadFile (ReaderT r m) where
    withFilePath fp (ReaderT m) = ReaderT (withFilePath fp . m)
    getFilePath = lift getFilePath

instance MonadFile m => MonadFile (ExceptT e m) where
    withFilePath fp (ExceptT m) = ExceptT (withFilePath fp m)
    getFilePath = lift getFilePath
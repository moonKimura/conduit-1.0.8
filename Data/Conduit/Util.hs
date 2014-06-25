-- | Various utility functions versions of @conduit@.
module Data.Conduit.Util
    ( -- * Misc
      zip
    , zipSinks
    ) where

import Prelude hiding (zip)
import Control.Monad (liftM, liftM2)
import Data.Conduit.Internal (Pipe (..), Source, Sink, injectLeftovers, ConduitM (..))
import Data.Void (Void, absurd)

-- | Combines two sources. The new source will stop producing once either
--   source has been exhausted.
--
-- Since 0.3.0
zip :: Monad m => Source m a -> Source m b -> Source m (a, b)
zip (ConduitM left0) (ConduitM right0) =
    ConduitM $ go left0 right0
  where
    go (Leftover left ()) right = go left right
    go left (Leftover right ())  = go left right
    go (Done ()) (Done ()) = Done ()
    go (Done ()) (HaveOutput _ close _) = PipeM (close >> return (Done ()))
    go (HaveOutput _ close _) (Done ()) = PipeM (close >> return (Done ()))
    go (Done ()) (PipeM _) = Done ()
    go (PipeM _) (Done ()) = Done ()
    go (PipeM mx) (PipeM my) = PipeM (liftM2 go mx my)
    go (PipeM mx) y@HaveOutput{} = PipeM (liftM (\x -> go x y) mx)
    go x@HaveOutput{} (PipeM my) = PipeM (liftM (go x) my)
    go (HaveOutput srcx closex x) (HaveOutput srcy closey y) = HaveOutput (go srcx srcy) (closex >> closey) (x, y)
    go (NeedInput _ c) right = go (c ()) right
    go left (NeedInput _ c) = go left (c ())

-- | Combines two sinks. The new sink will complete when both input sinks have
--   completed.
--
-- Any leftovers are discarded.
--
-- Since 0.4.1
zipSinks :: Monad m => Sink i m r -> Sink i m r' -> Sink i m (r, r')
zipSinks (ConduitM x0) (ConduitM y0) =
    ConduitM $ injectLeftovers x0 >< injectLeftovers y0
  where
    (><) :: Monad m => Pipe Void i Void () m r1 -> Pipe Void i Void () m r2 -> Pipe l i o () m (r1, r2)

    Leftover _  i    >< _                = absurd i
    _                >< Leftover _  i    = absurd i
    HaveOutput _ _ o >< _                = absurd o
    _                >< HaveOutput _ _ o = absurd o

    PipeM mx         >< y                = PipeM (liftM (>< y) mx)
    x                >< PipeM my         = PipeM (liftM (x ><) my)
    Done x           >< Done y           = Done (x, y)
    NeedInput px cx  >< NeedInput py cy  = NeedInput (\i -> px i >< py i) (\() -> cx () >< cy ())
    NeedInput px cx  >< y@Done{}         = NeedInput (\i -> px i >< y)    (\u -> cx u >< y)
    x@Done{}         >< NeedInput py cy  = NeedInput (\i -> x >< py i)    (\u -> x >< cy u)

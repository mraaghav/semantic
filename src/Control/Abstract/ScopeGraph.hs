{-# LANGUAGE GADTs, KindSignatures, LambdaCase, RankNTypes, ScopedTypeVariables, TypeOperators #-}
module Control.Abstract.ScopeGraph
  ( runScopeEnv
  , ScopeEnv
  , lookup
  , declare
  , reference
  , newScope
  , Declaration(..)
  , Reference(..)
  , EdgeLabel(..)
  , currentScope
  ) where

import           Control.Abstract.Evaluator
import           Control.Abstract.Heap
import           Data.Abstract.Name
import           Data.Abstract.ScopeGraph (Declaration (..), EdgeLabel, Reference, ScopeGraph)
import qualified Data.Abstract.ScopeGraph as ScopeGraph
import           Data.Span
import           Prelude hiding (lookup)
import           Prologue

data ScopeEnv address (m :: * -> *) a where
    Lookup :: Reference -> ScopeEnv address m (Maybe address)
    Declare :: Declaration -> Span -> ScopeEnv address m ()
    Reference :: Reference -> Declaration -> ScopeEnv address m ()
    Create :: Map EdgeLabel [address] -> ScopeEnv address m ()
    CurrentScope :: ScopeEnv address m address

lookup :: forall address value effects. Member (ScopeEnv address) effects => Reference -> Evaluator address value effects (Maybe address)
lookup = send . Lookup @address

declare :: forall address value effects. Member (ScopeEnv address) effects => Declaration -> Span -> Evaluator address value effects ()
declare = (send .) . Declare @address

reference :: forall address value effects. Member (ScopeEnv address) effects => Reference -> Declaration -> Evaluator address value effects ()
reference = (send .) . Reference @address

newScope :: forall address value effects. Member (ScopeEnv address) effects => Map EdgeLabel [address] -> Evaluator address value effects ()
newScope = send . Create @address

currentScope :: forall address value effects. Member (ScopeEnv address) effects => Evaluator address value effects address
currentScope = send CurrentScope

instance PureEffect (ScopeEnv address)
instance Effect (ScopeEnv address) where
  handleState c dist (Request (Lookup ref) k)         = Request (Lookup ref) (dist . (<$ c) . k)
  handleState c dist (Request (Declare decl ddata) k) = Request (Declare decl ddata) (dist . (<$ c) . k)
  handleState c dist (Request (Reference ref decl) k) = Request (Reference ref decl) (dist . (<$ c) . k)
  handleState c dist (Request (Create edges) k)       = Request (Create edges) (dist . (<$ c) . k)
  handleState c dist (Request CurrentScope k)         = Request CurrentScope (dist . (<$ c) . k)

runScopeEnv :: (Ord address, Effects effects, Member Fresh effects, Member (Allocator address) effects)
            => Evaluator address value (ScopeEnv address ': effects) a
            -> Evaluator address value effects (ScopeGraph address, a)
runScopeEnv evaluator = do
    name <- gensym
    address <- alloc name
    runState (ScopeGraph.emptyGraph address) (reinterpret handleScopeEnv evaluator)

handleScopeEnv :: forall address value effects a. (Ord address, Member Fresh effects, Member (Allocator address) effects)
          => ScopeEnv address (Eff (ScopeEnv address ': effects)) a
          -> Evaluator address value (State (ScopeGraph address) ': effects) a
handleScopeEnv = \case
    Lookup ref -> ScopeGraph.scopeOfRef ref <$> get
    Declare decl ddata -> modify @(ScopeGraph address) (ScopeGraph.declare decl ddata)
    Reference ref decl -> modify @(ScopeGraph address) (ScopeGraph.reference ref decl)
    Create edges -> do
        name <- gensym
        address <- alloc name
        modify @(ScopeGraph address) (ScopeGraph.create address edges)
    CurrentScope -> ScopeGraph.currentScope <$> get

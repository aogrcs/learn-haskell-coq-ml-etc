 https://www.schoolofhaskell.com/user/thoughtpolice/using-reflection
 https://www.reddit.com/r/haskell/comments/3hw90k/what_is_the_reflection_package_for/

GOAL: propogate values around via types using
- Kmett's : Data.Reflection : http://hackage.haskell.org/package/reflection
- this tutorial shows how it works, what it allows

> module R0 where
>
> import Data.Proxy
> import Data.Reflection

configurations problem
- propagate run-time preferences throughout a program
- allowing multiple concurrent conﬁguration sets to coexist safely under statically guaranteed separation

GHC `ImplicitParams` can do, but have concerns

reflection API:

data Proxy k = Proxy

class Reifies s a | s -> a where
  reflect :: proxy s -> a

newtype Magic a r = Magic (forall (s :: *). Reifies s a => Proxy s -> r)

reify :: forall a r. a -> (forall (s :: *). Reifies s a => Proxy s -> r) -> r
reify a k = unsafeCoerce (Magic k :: Magic a r) (const a) Proxy
{-# INLINE reify #-}


> p :: Reifies s a => Proxy s -> a
> p x = reflect x

> -- e1 :: Int
> e1 = reify 10 $ p -- \p -> reflect p + reflect p

> -- e2 :: Char
> e2 = reify 'c' $ \p -> reflect p

> -- e3 :: String
> e3 = reify 'c' $ \p -> show (reflect p)

- reify value 10 over the enclosed lambda
- inside the lambda, `reflect` `p` value to get `10 :: Int` back
- type of `reify` shows
- lambda accepts param of type `Proxy s`
- never had any instances of `Reifies` for the types
- how does it know what value to return, given the `Proxy`?

To understand
- look at the source of `reify`
- see how it elaborates to GHC Core

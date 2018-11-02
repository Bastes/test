module Simplify exposing
    ( Simplifier, simplify
    , noSimplify, unit, bool, order, int, atLeastInt, float, atLeastFloat, char, atLeastChar, character, string, maybe, result, lazylist, list, array, tuple, tuple3
    , convert, keepIf, dropIf, merge, map, andMap
    )

{-| Library containing a collection of basic simplifiers and helper functions to
make your own.

Simplifying is part of fuzzing, and the provided fuzzers have simplifiers already
built into them. You really only have to write your own simplifiers if you use
`Fuzz.custom`.


## Quick Reference

  - [Simplifying Basics](#simplifying-basics)
  - [Readymade Simplifiers](#readymade-simplifiers)
  - [Functions on Simplifiers](#functions-on-simplifiers)
  - [What are Simplifiers and why do we need them?](#what-are-simplifiers-and-why-do-we-need-them)


## Simplifying Basics

@docs Simplifier, simplify


## Readymade Simplifiers

@docs noSimplify, unit, bool, order, int, atLeastInt, float, atLeastFloat, char, atLeastChar, character, string, maybe, result, lazylist, list, array, tuple, tuple3


## Functions on Simplifiers

@docs convert, keepIf, dropIf, merge, map, andMap


## What are Simplifiers and why do we need them?

Fuzzers consist of two parts; a Generator and a Simplifier.

The Generator takes a random Seed as input and returns a random value of
the desired type, based on the Seed. When a test fails on one of those random
values, the simplifier takes the failing value and makes it simpler for you so
you can guess more easily what property of that value caused the test to fail.

Simplifying is a way to try and find the "simplest" (usually the "smallest")
example that fails, in order to give the tester better feedback on exactly
what went wrong.

Simplifiers are functions that, given a failing value, offer "simpler" values
to test against.


### What is "simple" (or small)?

That's kind of arbitrary, and depends on what kind of values you're fuzzing.
When you write your own Simplifier, you get to decide what is small for the
kind of data you're testing with.

Let's say I'm writing a Fuzzer for binary trees:

    -- randomly-generated binary trees might soon become unreadable
    type Tree a
        = Node (Tree a) (Tree a)
        | Leaf a

Now let's say its random Generator produced the following tree that makes the
test fail:

    Node
        (Node
            (Node
                (Node
                    (Leaf 888)
                    (Leaf 9090)
                )
                (Node
                    (Leaf -1)
                    (Node
                        (Leaf 731)
                        (Node
                            (Leaf 9621)
                            (Leaf -12)
                        )
                    )
                )
            )
            (Node
                (Leaf -350)
                (Leaf 124)
            )
        )
        (Node
            (Leaf 45)
            (Node
                (Leaf 123)
                (Node
                    (Leaf 999111)
                    (Leaf -148148)
                )
            )
        )

This is a pretty big tree, there are many nodes and leaves, and it's difficult
to tell which is responsible for the failure. If we don't attempt to find a
simpler value, the developer will have a hard time pointing out why it fails.

Now let's pass it through a simplifier, and test the resulting value until we
find this new simpler value that still fails the test:

    Leaf -1

Nice, looks like a negative number in a `Leaf` could be the issue.


### How does simplifying work?

A simplifier takes a value and returns a short list of simpler values that
hopefully fail too.

Once elm-test finds a failing fuzz test, it tries to simplify the input using
the simplifier. We'll then try the smaller values as inputs to that test. If one
of the smaller values also fail, we continue simplifying from there instead.
Once the simplifier says that there are no smaller values, or no smaller values
fail the fuzz test, we stop simplifying.

It's helpful to think of Simplifiers as returning simpler values rather than
smaller values. For example, 1 is simpler and smaller than 47142, and -1 is
bigger, yet still simpler than -47142.

Whether or not the simpler value is actually smaller isn't that important,
as long as we aren't simplifying in a loop. The bool simplifier simplifies True
to False, but not vice versa. If it did, and your test failed no matter if this
variable was True or False, there would always be a smaller/simpler value, so
we'd never stop simplifying! We would just re-test the same values over and over
again, forever!


### How do I make my own Simplifiers?

Simplifiers are deterministic, since they do not have access to a random number
generator. It's the generator part of the fuzzer that's meant to find the rare
edge cases; it's the simplifiers job to make the failures as understandable as
possible.

Simplifiers have to return a LazyList, something that works a bit like a list.
That LazyList may or may not have another element each time we ask for one,
and doesn't necessarily have them all committed to memory. That allows it to
take less space (interesting since there may be quite a lot of elements).

That LazyList should also provide a finite number of simpler values (if it
provided an infinite number of them, tests using it might continue indefinitely
at the simplifying phase).

Simplifiers must never simplify values in a circle, like:

    loopinBooleanSimplifier True == [ False ]

    loopinBooleanSimplifier False == [ True ]

Doing so will also result in tests looping indefinitely, testing and re-testing
the same values in a circle.

-}

import Array exposing (Array)
import Char
import Lazy exposing (Lazy, force, lazy)
import Lazy.List exposing (LazyList, append, cons, empty)
import List
import String


{-| The simplifier type.
A simplifier is a function that takes a value and returns a lazy list of values
that are in some sense "smaller" than the given value. If no such values exist,
then the simplifier should just return the empty list.
-}
type alias Simplifier a =
    a -> LazyList a


{-| Perform simplifying. Takes a predicate that returns `True` if you want
simplifying to continue (most likely the failing test for which we are attempting
to simplify the value). Also takes the simplifier and the value to simplify.

It returns the simpler value, or the input value if no simpler values that
satisfy the predicate are found.

-}
simplify : (a -> Bool) -> Simplifier a -> a -> a
simplify keepSimplifying simplifier originalVal =
    let
        helper lazyList val =
            case force lazyList of
                Lazy.List.Nil ->
                    val

                Lazy.List.Cons head tail ->
                    if keepSimplifying head then
                        helper (simplifier head) head

                    else
                        helper tail val
    in
    helper (simplifier originalVal) originalVal


{-| Perform no simplifying. Equivalent to the empty lazy list.
-}
noSimplify : Simplifier a
noSimplify _ =
    empty


{-| Simplify the empty tuple. Equivalent to `noSimplify`.
-}
unit : Simplifier ()
unit =
    noSimplify


{-| Simplifier of bools.
-}
bool : Simplifier Bool
bool b =
    case b of
        True ->
            cons False empty

        False ->
            empty


{-| Simplifier of `Order` values.
-}
order : Simplifier Order
order o =
    case o of
        GT ->
            cons EQ (cons LT empty)

        LT ->
            cons EQ empty

        EQ ->
            empty


{-| Simplifier of integers.
-}
int : Simplifier Int
int n =
    if n < 0 then
        cons -n (Lazy.List.map ((*) -1) (seriesInt 0 -n))

    else
        seriesInt 0 n


{-| Construct a simplifier of ints which considers the given int to
be most minimal.
-}
atLeastInt : Int -> Simplifier Int
atLeastInt min n =
    if n < 0 && n >= min then
        cons -n (Lazy.List.map ((*) -1) (seriesInt 0 -n))

    else
        seriesInt (max 0 min) n


{-| Simplifier of floats.
-}
float : Simplifier Float
float n =
    if n < 0 then
        cons -n (Lazy.List.map ((*) -1) (seriesFloat 0 -n))

    else
        seriesFloat 0 n


{-| Construct a simplifier of floats which considers the given float to
be most minimal.
-}
atLeastFloat : Float -> Simplifier Float
atLeastFloat min n =
    if n < 0 && n >= min then
        cons -n (Lazy.List.map ((*) -1) (seriesFloat 0 -n))

    else
        seriesFloat (max 0 min) n


{-| Simplifier of chars.
-}
char : Simplifier Char
char =
    convert Char.fromCode Char.toCode int


{-| Construct a simplifier of chars which considers the given char to
be most minimal.
-}
atLeastChar : Char -> Simplifier Char
atLeastChar ch =
    convert Char.fromCode Char.toCode (atLeastInt (Char.toCode ch))


{-| Simplifier of chars which considers the empty space as the most
minimal char and omits the control key codes.

Equivalent to:

    atLeastChar (Char.fromCode 32)

-}
character : Simplifier Char
character =
    atLeastChar (Char.fromCode 32)


{-| Simplifier of strings. Considers the empty string to be the most
minimal string and the space to be the most minimal char.

Equivalent to:

    convert String.fromList String.toList (list character)

-}
string : Simplifier String
string =
    convert String.fromList String.toList (list character)


{-| Maybe simplifier constructor.
Takes a simplifier of values and returns a simplifier of Maybes.
-}
maybe : Simplifier a -> Simplifier (Maybe a)
maybe simplifier m =
    case m of
        Just a ->
            cons Nothing (Lazy.List.map Just (simplifier a))

        Nothing ->
            empty


{-| Result simplifier constructor. Takes a simplifier of errors and a simplifier of
values and returns a simplifier of Results.
-}
result : Simplifier error -> Simplifier value -> Simplifier (Result error value)
result simplifyError simplifyValue r =
    case r of
        Ok value ->
            Lazy.List.map Ok (simplifyValue value)

        Err error ->
            Lazy.List.map Err (simplifyError error)


{-| Lazy List simplifier constructor. Takes a simplifier of values and returns a
simplifier of Lazy Lists. The lazy list being simplified must be finite. (I mean
really, how do you simplify infinity?)
-}
lazylist : Simplifier a -> Simplifier (LazyList a)
lazylist simplifier l =
    lazy <|
        \() ->
            let
                n : Int
                n =
                    Lazy.List.length l

                simplifyOneHelp : LazyList a -> LazyList (LazyList a)
                simplifyOneHelp lst =
                    lazy <|
                        \() ->
                            case force lst of
                                Lazy.List.Nil ->
                                    force empty

                                Lazy.List.Cons x xs ->
                                    force
                                        (append (Lazy.List.map (\val -> cons val xs) (simplifier x))
                                            (Lazy.List.map (cons x) (simplifyOneHelp xs))
                                        )

                removes : Int -> Int -> Simplifier (LazyList a)
                removes k_ n_ l_ =
                    lazy <|
                        \() ->
                            if k_ > n_ then
                                force empty

                            else if Lazy.List.isEmpty l_ then
                                force (cons empty empty)

                            else
                                let
                                    first =
                                        Lazy.List.take k_ l_

                                    rest =
                                        Lazy.List.drop k_ l_
                                in
                                force <|
                                    cons rest (Lazy.List.map (append first) (removes k_ (n_ - k_) rest))
            in
            force <|
                append
                    (Lazy.List.andThen (\k -> removes k n l)
                        (Lazy.List.takeWhile (\x -> x > 0) (Lazy.List.iterate (\num -> num // 2) n))
                    )
                    (simplifyOneHelp l)


{-| List simplifier constructor.
Takes a simplifier of values and returns a simplifier of Lists.
-}
list : Simplifier a -> Simplifier (List a)
list simplifier =
    convert Lazy.List.toList Lazy.List.fromList (lazylist simplifier)


{-| Array simplifier constructor.
Takes a simplifier of values and returns a simplifier of Arrays.
-}
array : Simplifier a -> Simplifier (Array a)
array simplifier =
    convert Lazy.List.toArray Lazy.List.fromArray (lazylist simplifier)


{-| 2-Tuple simplifier constructor.
Takes a tuple of simplifiers and returns a simplifier of tuples.
-}
tuple : ( Simplifier a, Simplifier b ) -> Simplifier ( a, b )
tuple ( simplifyA, simplifyB ) ( a, b ) =
    append (Lazy.List.map (Tuple.pair a) (simplifyB b))
        (append (Lazy.List.map (\first -> ( first, b )) (simplifyA a))
            (Lazy.List.map2 Tuple.pair (simplifyA a) (simplifyB b))
        )


{-| 3-Tuple simplifier constructor.
Takes a tuple of simplifiers and returns a simplifier of tuples.
-}
tuple3 : ( Simplifier a, Simplifier b, Simplifier c ) -> Simplifier ( a, b, c )
tuple3 ( simplifyA, simplifyB, simplifyC ) ( a, b, c ) =
    append (Lazy.List.map (\c1 -> ( a, b, c1 )) (simplifyC c))
        (append (Lazy.List.map (\b2 -> ( a, b2, c )) (simplifyB b))
            (append (Lazy.List.map (\a2 -> ( a2, b, c )) (simplifyA a))
                (append (Lazy.List.map2 (\b2 c2 -> ( a, b2, c2 )) (simplifyB b) (simplifyC c))
                    (append (Lazy.List.map2 (\a2 c2 -> ( a2, b, c2 )) (simplifyA a) (simplifyC c))
                        (append (Lazy.List.map2 (\a2 b2 -> ( a2, b2, c )) (simplifyA a) (simplifyB b))
                            (Lazy.List.map3 (\a2 b2 c2 -> ( a2, b2, c2 )) (simplifyA a) (simplifyB b) (simplifyC c))
                        )
                    )
                )
            )
        )



----------------------
-- HELPER FUNCTIONS --
----------------------


{-| Convert a Simplifier of a's into a Simplifier of b's using two inverse functions.
)
If you use this function as follows:

    simplifierB =
        convert f g simplifierA

Make sure that:

    `f(g(x)) == x` for all x
    -- (putting something into g then feeding the output into f must give back
    -- just that original something, whatever it is)

Or else this process will generate garbage.

-}
convert : (a -> b) -> (b -> a) -> Simplifier a -> Simplifier b
convert f g simplifier b =
    Lazy.List.map f (simplifier (g b))


{-| Filter out the results of a simplifier. The resulting simplifier
will only produce simpler values which satisfy the given predicate.
-}
keepIf : (a -> Bool) -> Simplifier a -> Simplifier a
keepIf predicate simplifier a =
    Lazy.List.keepIf predicate (simplifier a)


{-| Filter out the results of a simplifier. The resulting simplifier
will only throw away simpler values which satisfy the given predicate.
-}
dropIf : (a -> Bool) -> Simplifier a -> Simplifier a
dropIf predicate =
    keepIf (not << predicate)


{-| Merge two simplifiers. Generates all the values in the first
simplifier, and then all the non-duplicated values in the second
simplifier.
-}
merge : Simplifier a -> Simplifier a -> Simplifier a
merge simplify1 simplify2 a =
    Lazy.List.unique (append (simplify1 a) (simplify2 a))


{-| Re-export of `Lazy.List.map`
This is useful in order to compose simplifiers, especially when used in
conjunction with `andMap`. For example:

    type alias Vector =
        { x : Float
        , y : Float
        , z : Float
        }

    vector : Simplifier Vector
    vector { x, y, z } =
        Vector
            `map` float x
            `andMap` float y
            `andMap` float z

-}
map : (a -> b) -> LazyList a -> LazyList b
map =
    Lazy.List.map


{-| Apply a lazy list of functions on a lazy list of values.

The argument order is so that it is easy to use in `|>` chains.

-}
andMap : LazyList a -> LazyList (a -> b) -> LazyList b
andMap =
    Lazy.List.andMap



-----------------------
-- PRIVATE FUNCTIONS --
-----------------------


seriesInt : Int -> Int -> LazyList Int
seriesInt low high =
    if low >= high then
        empty

    else if low == high - 1 then
        cons low empty

    else
        let
            low_ =
                low + ((high - low) // 2)
        in
        cons low (seriesInt low_ high)


seriesFloat : Float -> Float -> LazyList Float
seriesFloat low high =
    if low >= high - 0.0001 then
        if high /= 0.000001 then
            Lazy.List.singleton (low + 0.000001)

        else
            empty

    else
        let
            low_ =
                low + ((high - low) / 2)
        in
        cons low (seriesFloat low_ high)

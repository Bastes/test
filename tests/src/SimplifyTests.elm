module SimplifyTests exposing (all)

import Expect
import Simplify
import Test exposing (..)


all : Test
all =
    describe "Simplify"
        [ describe "list" <|
            let
                simplify =
                    Simplify.simplify (always True) (Simplify.list Simplify.unit)
            in
            [ test "empty list does not simplify" <|
                \() ->
                    simplify []
                        |> Expect.equal []
            , test "singleton list simplifies to empty" <|
                \() ->
                    simplify [ () ]
                        |> Expect.equal []
            ]
        ]

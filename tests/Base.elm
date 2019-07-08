module Base exposing (roundtrips, suite)

import Bytes.Encode
import Codec exposing (Codec)
import Dict
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer)
import Set
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "Testing roundtrips"
        [ describe "Basic" basicTests
        , describe "Containers" containersTests
        , describe "Object" objectTests
        , describe "Custom" customTests
        , describe "bimap" bimapTests
        , describe "maybe" maybeTests
        , describe "constant"
            [ test "roundtrips"
                (\_ ->
                    Codec.constant 632
                        |> (\d -> Codec.decodeValue d (Bytes.Encode.sequence [] |> Bytes.Encode.encode))
                        |> Expect.equal (Just 632)
                )
            ]
        , describe "recursive" recursiveTests
        ]


roundtrips : Fuzzer a -> Codec a -> Test
roundtrips fuzzer codec =
    fuzz fuzzer "is a roundtrip" <|
        \value ->
            value
                |> Codec.encodeToValue codec
                |> Codec.decodeValue codec
                |> Expect.equal (Just value)


roundtripsWithin : Fuzzer Float -> Codec Float -> Test
roundtripsWithin fuzzer codec =
    fuzz fuzzer "is a roundtrip" <|
        \value ->
            value
                |> Codec.encodeToValue codec
                |> Codec.decodeValue codec
                |> Maybe.withDefault -999.1234567
                |> Expect.within (Expect.Relative 0.000001) value


basicTests : List Test
basicTests =
    [ describe "Codec.string"
        [ roundtrips Fuzz.string Codec.string
        ]
    , describe "Codec.signedInt"
        [ roundtrips signedInt32Fuzz Codec.signedInt
        ]
    , describe "Codec.unsignedInt"
        [ roundtrips unsignedInt32Fuzz Codec.unsignedInt
        ]
    , describe "Codec.float64"
        [ roundtrips Fuzz.float Codec.float64
        ]
    , describe "Codec.float32"
        [ roundtripsWithin Fuzz.float Codec.float32
        ]
    , describe "Codec.bool"
        [ roundtrips Fuzz.bool Codec.bool
        ]
    , describe "Codec.char"
        [ roundtrips Fuzz.char Codec.char
        ]
    ]


containersTests : List Test
containersTests =
    [ describe "Codec.array"
        [ roundtrips (Fuzz.array signedInt32Fuzz) (Codec.array Codec.signedInt)
        ]
    , describe "Codec.list"
        [ roundtrips (Fuzz.list signedInt32Fuzz) (Codec.list Codec.signedInt)
        ]
    , describe "Codec.dict"
        [ roundtrips
            (Fuzz.map2 Tuple.pair Fuzz.string signedInt32Fuzz
                |> Fuzz.list
                |> Fuzz.map Dict.fromList
            )
            (Codec.dict Codec.string Codec.signedInt)
        ]
    , describe "Codec.set"
        [ roundtrips
            (Fuzz.list signedInt32Fuzz |> Fuzz.map Set.fromList)
            (Codec.set Codec.signedInt)
        ]
    , describe "Codec.tuple"
        [ roundtrips
            (Fuzz.tuple ( signedInt32Fuzz, signedInt32Fuzz ))
            (Codec.tuple Codec.signedInt Codec.signedInt)
        ]
    ]


unsignedInt32Fuzz =
    Fuzz.intRange 0 4294967295


signedInt32Fuzz =
    Fuzz.intRange -2147483648 2147483647


objectTests : List Test
objectTests =
    [ describe "with 0 fields"
        [ roundtrips (Fuzz.constant {})
            (Codec.object {}
                |> Codec.buildObject
            )
        ]
    , describe "with 1 field"
        [ roundtrips (Fuzz.map (\i -> { fname = i }) signedInt32Fuzz)
            (Codec.object (\i -> { fname = i })
                |> Codec.field .fname Codec.signedInt
                |> Codec.buildObject
            )
        ]
    , describe "with 2 fields"
        [ roundtrips
            (Fuzz.map2
                (\a b ->
                    { a = a
                    , b = b
                    }
                )
                signedInt32Fuzz
                signedInt32Fuzz
            )
            (Codec.object
                (\a b ->
                    { a = a
                    , b = b
                    }
                )
                |> Codec.field .a Codec.signedInt
                |> Codec.field .b Codec.signedInt
                |> Codec.buildObject
            )
        ]
    ]


type Newtype a
    = Newtype a


type Newtype6 a b c d e f
    = Newtype6 a b c d e f


customTests : List Test
customTests =
    [ describe "with 1 ctor, 0 args"
        [ roundtrips (Fuzz.constant ())
            (Codec.custom
                (\f v ->
                    case v of
                        () ->
                            f
                )
                |> Codec.variant0 0 ()
                |> Codec.buildCustom
            )
        ]
    , describe "with 1 ctor, 1 arg"
        [ roundtrips (Fuzz.map Newtype signedInt32Fuzz)
            (Codec.custom
                (\f v ->
                    case v of
                        Newtype a ->
                            f a
                )
                |> Codec.variant1 1 Newtype Codec.signedInt
                |> Codec.buildCustom
            )
        ]
    , describe "with 1 ctor, 1 arg, different id codec"
        [ roundtrips (Fuzz.map Newtype signedInt32Fuzz)
            (Codec.customWithIdCodec Codec.unsignedInt8
                (\f v ->
                    case v of
                        Newtype a ->
                            f a
                )
                |> Codec.variant1 1 Newtype Codec.signedInt
                |> Codec.buildCustom
            )
        ]
    , describe "with 1 ctor, 6 arg"
        [ roundtrips (Fuzz.map5 (Newtype6 0) signedInt32Fuzz signedInt32Fuzz signedInt32Fuzz signedInt32Fuzz signedInt32Fuzz)
            (Codec.custom
                (\function v ->
                    case v of
                        Newtype6 a b c d e f ->
                            function a b c d e f
                )
                |> Codec.variant6 1 Newtype6 Codec.signedInt Codec.signedInt Codec.signedInt Codec.signedInt Codec.signedInt Codec.signedInt
                |> Codec.buildCustom
            )
        ]
    , describe "with 2 ctors, 0,1 args" <|
        let
            match fnothing fjust value =
                case value of
                    Nothing ->
                        fnothing

                    Just v ->
                        fjust v

            codec =
                Codec.custom match
                    -- Use a negative id here just to make sure the default id codec handles negative values
                    |> Codec.variant0 -1 Nothing
                    |> Codec.variant1 0 Just Codec.signedInt
                    |> Codec.buildCustom

            fuzzers =
                [ ( "1st ctor", Fuzz.constant Nothing )
                , ( "2nd ctor", Fuzz.map Just signedInt32Fuzz )
                ]
        in
        fuzzers
            |> List.map
                (\( name, fuzz ) ->
                    describe name
                        [ roundtrips fuzz codec ]
                )
    ]


bimapTests : List Test
bimapTests =
    [ roundtrips Fuzz.float <|
        Codec.map
            (\x -> x * 2)
            (\x -> x / 2)
            Codec.float64
    ]


maybeTests : List Test
maybeTests =
    [ describe "single"
        [ roundtrips
            (Fuzz.oneOf
                [ Fuzz.constant Nothing
                , Fuzz.map Just signedInt32Fuzz
                ]
            )
          <|
            Codec.maybe Codec.signedInt
        ]
    ]


recursiveTests : List Test
recursiveTests =
    [ describe "list"
        [ roundtrips (Fuzz.list signedInt32Fuzz) <|
            Codec.recursive
                (\c ->
                    Codec.custom
                        (\fempty fcons value ->
                            case value of
                                [] ->
                                    fempty

                                x :: xs ->
                                    fcons x xs
                        )
                        |> Codec.variant0 0 []
                        |> Codec.variant2 1 (::) Codec.signedInt c
                        |> Codec.buildCustom
                )
        ]
    ]

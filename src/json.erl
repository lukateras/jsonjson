%% Minimal JSON parsing module that both encodes and decodes.
%% When encoding, JSON types are mapped to Erlang terms as follows:
%%
%% * JSON object is Erlang map
%% * JSON string is Erlang binary
%% * JSON list is Erlang list
%% * JSON numbers are Erlang numbers
%%
%% When decoding, everything is vice versa except strings. Strings are
%% parsed to lists. You can alter this behavior to fit your preferences
%% by editing decode_string/2 in this file.

-module(json).

-export([encode/1, decode/1]).
-define(is_digit(X), X >= 48, X =< 57).
-define(is_space(X), X == $\t; X == $\s; X == $\t; X == $\n).
-define(is_exponent(X), X == $e; X == $E; X == $+; X == $-).

encode(Bin) when is_binary(Bin) -> encode_string(Bin, []);
encode(I) when is_integer(I) -> integer_to_binary(I);
encode(F) when is_float(F) -> float_to_binary(F);
encode(M) when is_map(M) -> encode_map(maps:to_list(M), []);
encode(L) when is_list(L) -> encode_list(L, []);
encode(true) -> <<"true">>;
encode(false) -> <<"false">>;
encode(null) -> <<"null">>;
encode(A) when is_atom(A) -> encode(list_to_binary(atom_to_list(A))).

encode_string(<<>>, Buf) -> [$", lists:reverse(Buf), $"];
encode_string(<<$\r, T/binary>>, Buf) -> encode_string(T, ["\\r"|Buf]);
encode_string(<<$\t, T/binary>>, Buf) -> encode_string(T, ["\\t"|Buf]);
encode_string(<<$\n, T/binary>>, Buf) -> encode_string(T, ["\\n"|Buf]);
encode_string(<<$\f, T/binary>>, Buf) -> encode_string(T, ["\\f"|Buf]);
encode_string(<<$", T/binary>>, Buf) -> encode_string(T, ["\\\""|Buf]);
encode_string(<<$\\, T/binary>>, Buf) -> encode_string(T, ["\\\\"|Buf]);
encode_string(<<H, T/binary>>, Buf) -> encode_string(T, [H|Buf]).

encode_list([], Buf) -> [$[, lists:reverse(Buf), $]];
encode_list([H], Buf) -> encode_list([], [encode(H) | Buf]); 
encode_list([H|T], Buf) -> encode_list(T, [$, | [encode(H) | Buf]]).

encode_map([], Buf) -> [${, lists:reverse(Buf), $}];
encode_map([H], Buf) -> encode_map([], [encode_pair(H) | Buf]); 
encode_map([H|T], Buf) -> encode_map(T, [$, | [encode_pair(H) | Buf]]).

encode_pair({K,V}) -> 
    Key = encode(K), Value = encode(V), 
    [Key, $:, Value].

decode(String) when is_list(String) -> decode(list_to_binary(String));
decode(Bin) when is_binary(Bin) ->
    try
        decode(Bin, [])
    of
        {_, Value} -> {ok, Value}
    catch
       error:Error -> {error, Error} 
    end.

decode(<<$", T/binary>>, []) -> decode_string(T, []);
decode(<<$[, T/binary>>, []) -> decode_list(T, []);
decode(<<${, T/binary>>, []) -> decode_map(T, #{});

decode(<<H, T/binary>>, []) when ?is_space(H) -> decode(T, []);

decode(<<$t, T/binary>>, []) -> decode(T, t);
decode(<<$r, T/binary>>, t) -> decode(T, tr);
decode(<<$u, T/binary>>, tr) -> decode(T, tru);
decode(<<$e, T/binary>>, tru) -> {T, true};

decode(<<$f, T/binary>>, []) -> decode(T, f);
decode(<<$a, T/binary>>, f) -> decode(T, fa);
decode(<<$l, T/binary>>, fa) -> decode(T, fal);
decode(<<$s, T/binary>>, fal) -> decode(T, fals);
decode(<<$e, T/binary>>, fals) -> {T, false};

decode(<<$n, T/binary>>, []) -> decode(T, n);
decode(<<$u, T/binary>>, n) -> decode(T, nu);
decode(<<$l, T/binary>>, nu) -> decode(T, nul);
decode(<<$l, T/binary>>, nul) -> {T, null};

decode(<<H, T/binary>>, []) when ?is_digit(H); H == $- -> decode_integer(T, [H]).

decode_integer(<<H, T/binary>>, Buf) when ?is_digit(H) -> decode_integer(T, [H|Buf]);
decode_integer(<<$., T/binary>>, Buf) -> decode_float(T, [$.|Buf]);
decode_integer(Bin, Buf) -> {Bin, list_to_integer(lists:reverse(Buf))}.

decode_float(<<H, T/binary>>, Buf) when ?is_digit(H); ?is_exponent(H) ->
    decode_float(T, [H|Buf]);
decode_float(Bin, Buf) ->
    {Bin, list_to_float(lists:reverse(Buf))}.

decode_string(<<$", T/binary>>, Buf) -> {T, lists:reverse(Buf)};
decode_string(<<$\\, $u, C1, C2, C3, C4, T/binary>>, Buf) ->
    Code = list_to_integer([C1, C2, C3, C4], 16),
    Char = unicode:characters_to_list([Code], utf8),
    decode_string(T, [Char|Buf]);
decode_string(<<$\\, Char, T/binary>>, Buf) ->
    SpecialChar = case Char of
        $b -> $\s;
        $f -> $\f;
        $n -> $\n;
        $r -> $\r;
        $t -> $\t;
        Char -> Char
    end,
    decode_string(T, [SpecialChar|Buf]);
decode_string(<<H, T/binary>>, Buf) -> decode_string(T, [H|Buf]).

decode_list(<<$], T/binary>>, List) -> {T, lists:reverse(List)};
decode_list(<<H, T/binary>>, List) when ?is_space(H); H == $, -> decode_list(T, List);
decode_list(Bin, List) ->
    {Rest, Value} = decode(Bin, []),
    decode_list(Rest, [Value|List]).

decode_map(<<$}, T/binary>>, Map) -> {T, Map};
decode_map(<<$,, T/binary>>, Map) -> decode_map(T, Map);
decode_map(<<H, T/binary>>, Map) when ?is_space(H) -> decode_map(T, Map);
decode_map(Bin, Map) ->
    {Rest1, Key} = decode(Bin, []),
    {Rest2, ok} = decode_colon(Rest1),
    {Rest3, Value} = decode(Rest2, []),
    decode_map(Rest3, maps:put(Key, Value, Map)).

decode_colon(<<$:, T/binary>>) -> {T, ok};
decode_colon(<<H, T/binary>>) when ?is_space(H) -> decode_colon(T).

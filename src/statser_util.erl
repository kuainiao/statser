-module(statser_util).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("statser.hrl").

-export([ceiling/1,
         floor/1]).


floor(X) when X < 0 ->
    Truncated = trunc(X),
    case X - Truncated == 0 of
       true -> Truncated;
       false -> Truncated - 1
    end;
floor(X) ->
    trunc(X).


ceiling(X) when X < 0 ->
    trunc(X);
ceiling(X) ->
    Truncated = trunc(X),
    case X - Truncated == 0 of
       true -> Truncated;
       false -> Truncated + 1
    end.

%%
%% TESTS
%%

-ifdef(TEST).

floor_test_() ->
    [?_assertEqual(5, floor(5.0)),
     ?_assertEqual(5, floor(5)),
     ?_assertEqual(5, floor(5.5)),
     ?_assertEqual(5, floor(5.9)),
     ?_assertEqual(-6, floor(-6)),
     ?_assertEqual(-6, floor(-5.1)),
     ?_assertEqual(-6, floor(-5.9))
    ].

ceiling_test_() ->
    [?_assertEqual(5, ceiling(5.0)),
     ?_assertEqual(5, ceiling(5)),
     ?_assertEqual(6, ceiling(5.5)),
     ?_assertEqual(6, ceiling(5.9)),
     ?_assertEqual(-5, ceiling(-5)),
     ?_assertEqual(-5, ceiling(-5.1)),
     ?_assertEqual(-5, ceiling(-5.9))
    ].

-endif.

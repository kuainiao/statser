-module(statser_instrumentation).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-behaviour(gen_server).

%% API
-export([start_link/0,
         increment/1,
         increment/2,
         append/2]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {metrics, path, timer}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


increment(Key) -> increment(Key, 1).

increment(Key, Amount) ->
    gen_server:cast(?MODULE, {increment, Key, Amount}).


append(Key, Value) ->
    gen_server:cast(?MODULE, {append, Key, Value}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    lager:info("starting instrumentation service at ~p", [self()]),
    gen_server:cast(self(), prepare),

    {ok, #state{metrics=maps:new()}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(prepare, State) ->
    % TODO: sanitize hostname
    {ok, Hostname} = inet:gethostname(),
    HostnameBS = list_to_binary(Hostname),
    Path = <<"statser.instrumentation.", HostnameBS/binary, ".">>,

    % TODO: determine interval from configuration
    Interval = 60 * 1000,

    lager:info("preparing instrumentation service timer with interval of ~w ms", [Interval]),

    {ok, Timer} = timer:send_interval(Interval, update_metrics),
    {noreply, State#state{path=Path, timer=Timer}};

handle_cast({increment, Key, Amount}, State) ->
    Map = increment_metrics(Key, Amount, State#state.metrics),
    {noreply, State#state{metrics=Map}};

handle_cast({append, Key, Value}, State) ->
    Map = append_metrics(Key, Value, State#state.metrics),
    {noreply, State#state{metrics=Map}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(update_metrics, State) ->
    Now = erlang:system_time(second),
    Path = State#state.path,
    Metrics = State#state.metrics,
    lager:debug("instrumentation: handle metrics update - current ~p", [Metrics]),

    % TODO: handle list values as well
    UpdatedM = maps:fold(fun(K, V, Map) when is_number(V) ->
                                 publish(K, V, Now, Path),
                                 maps:put(K, 0, Map);
                            (_K, _V, Map) -> Map
                         end, Metrics, Metrics),

    {noreply, State#state{metrics=UpdatedM}};

handle_info(Info, State) ->
    lager:warning("instrumentation: unhandled message ~p", [Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, #state{timer=Timer}) ->
    lager:info("terminating instrumentation service at ~w", [self()]),
    timer:cancel(Timer),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

publish(Key, Value, TS, Path) ->
    Metric = <<Path/binary, Key/binary>>,
    gen_server:cast(statser_router, {line, Metric, Value, TS}).


increment_metrics(Key, Amount, Map) when is_number(Amount) ->
    Update = fun(Value) when is_number(Value) -> Value + Amount;
                (Value) -> Value end,
    maps:update_with(Key, Update, Amount, Map);
increment_metrics(_Key, _Amount, Map) -> Map.


append_metrics(Key, Value, Map) when is_number(Value) ->
    Update = fun(Values) when is_list(Values) -> [Value | Values];
                (Values) -> Values end,
    maps:update_with(Key, Update, [Value], Map);
append_metrics(_Key, _Value, Map) -> Map.


%%%===================================================================
%%% Tests
%%%===================================================================

-ifdef(TEST).

increment_metrics_test_() ->
    [?_assertEqual(#{"foo" => 1}, increment_metrics("foo", 1, #{})),
     ?_assertEqual(#{"foo" => 36}, increment_metrics("foo", 2, #{"foo" => 34})),
     ?_assertEqual(#{"foo" => 20, "bar" => 25}, increment_metrics("foo", 10, #{"bar" => 25, "foo" => 10})),
     ?_assertEqual(#{"bar" => 25}, increment_metrics("foo", none, #{"bar" => 25}))
    ].


append_metrics_test_() ->
    [?_assertEqual(#{"foo" => [1]}, append_metrics("foo", 1, #{})),
     ?_assertEqual(#{"foo" => [2, 1]}, append_metrics("foo", 2, #{"foo" => [1]})),
     ?_assertEqual(#{"foo" => [8, 1], "bar" => 34}, append_metrics("foo", 8, #{"foo" => [1], "bar" => 34})),
     ?_assertEqual(#{"foo" => 9}, append_metrics("foo", 9, #{"foo" => 9}))
    ].


-endif. % TEST

%%  This Source Code Form is subject to the terms of the Mozilla Public
%%  License, v. 2.0. If a copy of the MPL was not distributed with this
%%  file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%
-module(rabbit_udp_exchange).
-include_lib("rabbit_common/include/rabbit.hrl").
-include("rabbit_udp_exchange.hrl").

-define(EXCHANGE_TYPE_BIN, <<"x-udp">>).

-behaviour(rabbit_exchange_type).

-rabbit_boot_step({?MODULE,
                   [{description, "exchange type x-udp"},
		    {mfa,         {rabbit_registry, register,
				   [exchange, ?EXCHANGE_TYPE_BIN, ?MODULE]}},
		    {cleanup,     {rabbit_registry, unregister,
				   [exchange, ?EXCHANGE_TYPE_BIN]}},
                    {requires,    rabbit_registry},
                    {enables,     recovery}]}).

-export([
    description/0,
    serialise_events/0,
    route/2,
    validate/1,
    validate_binding/2,
    create/2,
    delete/3,
    policy_changed/2,
    add_binding/3,
    remove_bindings/3,
    assert_args_equivalence/2,
    info/1,
    info/2
]).

-export([deliver/2]).

-export([truncate_bin/2]). %% utility

description() ->
    [{name, ?EXCHANGE_TYPE_BIN},
     {description, <<"UDP exchange">>}].

serialise_events() -> false.

%% Called when AMQP clients basic.publish to this exchange.
route(X, Delivery) ->
    rabbit_udp_exchange_sup:ensure_started_local(X) ! Delivery,
    [].

%% Called every time this exchange is declared, not just the first.
validate(X) ->
    _ = rabbit_udp_exchange_sup:endpoint_params(X),
    ok.

%% Called BEFORE declaration, to check args etc
validate_binding(_X, _B) -> ok.

%% Called just the first time the exchange is declared.
create(transaction, _X) ->
    ok;
create(none, X) ->
    rabbit_udp_exchange_sup:ensure_started(X),
    ok.

%% Called when we're finally deleted.
delete(transaction, _X, _Bs) ->
    ok;
delete(none, X, _Bs) ->
    rabbit_udp_exchange_sup:stop(X),
    ok.

policy_changed(_X1, _X2) -> ok.

add_binding(Tx, X, B) -> rabbit_exchange_type_topic:add_binding(Tx, X, B).
remove_bindings(Tx, X, Bs) -> rabbit_exchange_type_topic:remove_bindings(Tx, X, Bs).
assert_args_equivalence(X, Args) -> rabbit_exchange:assert_args_equivalence(X, Args).

info(_X) -> [].
info(_X, _) -> [].

%%-------------------------------------------------------------------------------------

%% We behave like a topic exchange.
deliver(X, Delivery) ->
    QueueNames = rabbit_exchange_type_topic:route(X, Delivery),
    Queues = rabbit_amqqueue:lookup(QueueNames),
    _QueuePids = rabbit_amqqueue:deliver(Queues, Delivery),
    ok.

truncate_bin(Limit, B) ->
    case B of
        <<X:Limit/binary, _/binary>> -> X;
        _ -> B
    end.

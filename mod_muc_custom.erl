%%%-------------------------------------------------------------------
%%% @author aadi
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 24. Apr 2020 1:31 PM
%%%-------------------------------------------------------------------
-module(mod_muc_custom).

-author("aadi").

-behaviour(gen_mod).

-include("logger.hrl").
-include("xmpp.hrl").
-include("mod_muc_room.hrl").


-record(user_info, {affiliation, present, subscribed}).

%% gen_mod API callbacks
-export([start/2, stop/1, depends/2, mod_options/1, on_muc_process_iq/2]).

start(_Host, _Opts) ->
    ?INFO_MSG("Hello, ejabberd world!", []),
    ejabberd_hooks:add(muc_process_iq, _Host, ?MODULE, on_muc_process_iq, 50),
    ok.

stop(_Host) ->
    ?INFO_MSG("Bye bye, ejabberd world!", []),
    ejabberd_hooks:delete(muc_process_iq, _Host, ?MODULE, on_muc_process_iq, 50),
    ok.

depends(_Host, _Opts) ->
    [].

mod_options(_Host) ->
    [].

on_muc_process_iq(IQ, MUCState) ->
    case xmpp:get_ns(hd(xmpp:get_els(IQ))) of
      <<"http://jabber.org/protocol/muc#extended">> ->
          M1 = maps:fold(fun (Jid, {Aff, _}, AccIn) ->
                                 maps:put(Jid,
                                          #user_info{affiliation = erlang:atom_to_binary(Aff, utf8),
                                                     present = <<"false">>,
                                                     subscribed = <<"false">>},
                                          AccIn)
                         end,
                         maps:new(),
                         MUCState#state.affiliations),
          M2 = maps:fold(fun (Key, _Value, Acc) ->
                                 {Luser, Lserver, _} = Key,
                                 Key1 = {Luser, Lserver, <<>>},
                                 case maps:is_key(Key1, Acc) of
                                   true ->
                                       Info = maps:get(Key1, Acc),
                                       maps:update(Key1, Info#user_info{present = <<"true">>}, Acc);
                                   _ ->
                                       maps:put(Key1,
                                                #user_info{affiliation = <<"none">>,
                                                           present = <<"true">>,
                                                           subscribed = <<"false">>},
                                                Acc)
                                 end
                         end,
                         M1,
                         MUCState#state.users),
          M3 = maps:fold(fun (Key, _Value, Acc) ->
                                 case maps:is_key(Key, Acc) of
                                   true ->
                                       Info = maps:get(Key, Acc),
                                       maps:update(Key,
                                                   Info#user_info{subscribed = <<"true">>},
                                                   Acc);
                                   _ ->
                                       maps:put(Key,
                                                #user_info{affiliation = <<"none">>,
                                                           present = <<"onlysubscribe">>,
                                                           subscribed = <<"true">>},
                                                Acc)
                                 end
                         end,
                         M2,
                         MUCState#state.subscribers),
          Children = maps:fold(fun (Key, UserInfo, Acc) ->
                                       [#xmlel{name = <<"item">>,
                                               attrs =
                                                   [{<<"jid">>, jid:to_string(Key)},
                                                    {<<"present">>, UserInfo#user_info.present},
                                                    {<<"affiliation">>,
                                                     UserInfo#user_info.affiliation},
                                                    {<<"subscribed">>,
                                                     UserInfo#user_info.subscribed}]}
                                        | Acc]
                               end,
                               [],
                               M3),
          SubEl = hd(xmpp:get_els(IQ)),
          IQRes = xmpp:make_iq_result(IQ),
          Res = xmpp:set_els(IQRes, [SubEl#xmlel{children = Children}]),
          ?INFO_MSG("mod_muc_custom retruns ~p~n", [Res]),
          ejabberd_router:route(Res),
          ignore;
      _ ->
          IQ
    end.

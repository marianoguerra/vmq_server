%% Copyright 2014 Erlio GmbH Basel Switzerland (http://erl.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(vmq_reg_sup).

-behaviour(supervisor).

%% API
-export([start_link/0,
         start_reg_view/1,
         stop_reg_view/1,
         reconfigure_registry/1]).

%% Supervisor callbacks
-export([init/1]).

-define(CHILD(Id, Mod, Type, Args), {Id, {Mod, start_link, Args},
                                     permanent, 5000, Type, [Mod]}).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    {ok, Pid} = supervisor:start_link({local, ?MODULE}, ?MODULE, []),
    DefaultRegView = vmq_config:get_env(default_reg_view, vmq_reg_trie),
    RegViews = lists:usort([DefaultRegView|vmq_config:get_env(reg_views, [])]),
    _ = [{ok, _} = start_reg_view(RV) || RV <- RegViews],
    {ok, Pid}.

start_reg_view(ViewModule) ->
    supervisor:start_child(?MODULE, reg_view_child_spec(ViewModule)).

stop_reg_view(ViewModule) ->
    ChildId = {reg_view, ViewModule},
    case supervisor:terminate_child(?MODULE, ChildId) of
        ok ->
            supervisor:delete_child(?MODULE, ChildId);
        {error, Reason} ->
            {error, Reason}
    end.

reconfigure_registry(Config) ->
    case lists:keyfind(reg_views, 1, Config) of
        {_, RegViews} ->
            DefaultRegView = vmq_config:get_env(default_reg_view, vmq_reg_trie),
            RequiredRegViews = lists:usort([DefaultRegView|RegViews]),
            InstalledRegViews = [Id || {{reg_view, Id}, _, _, _}
                                       <- supervisor:which_children(?MODULE)],
            ToBeInstalled = RequiredRegViews -- InstalledRegViews,
            ToBeUnInstalled = InstalledRegViews -- RequiredRegViews,
            _ = [{ok, _} = start_reg_view(RV) || RV <- ToBeInstalled],
            _ = [{ok, _} = stop_reg_view(RV) || RV <- ToBeUnInstalled];
        false ->
            ok
    end.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    {ok, {{one_for_one, 5, 10},
          [?CHILD(vmq_reg, vmq_reg, worker, []),
           ?CHILD(vmq_reg_leader, vmq_reg_leader, worker, []),
           ?CHILD(vmq_session_expirer, vmq_session_expirer, worker, [])]
         }
    }.

%%%===================================================================
%%% Internal functions
%%%===================================================================
reg_view_child_spec(ViewModule) ->
    ?CHILD({reg_view, ViewModule}, ViewModule, worker, []).
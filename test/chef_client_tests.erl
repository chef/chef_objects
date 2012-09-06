%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92-*-
%% ex: ts=4 sw=4 et
%% @author James Casey <james@opscode.com>
%% @author Seth Falcon <seth@opscode.com>
%% Copyright 2012 Opscode, Inc. All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%


-module(chef_client_tests).

-include_lib("chef_objects/include/chef_types.hrl").
-include_lib("chef_objects/include/chef_osc_defaults.hrl").
-include_lib("eunit/include/eunit.hrl").

public_key_data() ->
    {ok, Bin} = file:read_file("../test/spki_public.pem"),
    Bin.

cert_data() ->
    {ok, Bin} = file:read_file("../test/cert.pem"),
    Bin.

set_key_pair_test_() ->
    Ejson = {[]},
    PrivateKey = <<"private">>,
    DataForType = fun(key) ->
                          public_key_data();
                     (cert) ->
                          cert_data()
                  end,
    KeyForType = fun(key) ->
                         <<"public_key">>;
                    (cert) ->
                         <<"certificate">>
                 end,
    NotKeyForType = fun(key) ->
                            <<"certificate">>;
                       (cert) ->
                            <<"public_key">>
                    end,
    Tests = [
             begin
                 Got = chef_client:set_key_pair(Ejson,
                                                {public_key, DataForType(Type)},
                                                {private_key, PrivateKey}),
                 [?_assertEqual(PrivateKey, ej:get({<<"private_key">>}, Got)),
                  ?_assertEqual(DataForType(Type), ej:get({KeyForType(Type)}, Got)),
                  ?_assertEqual(undefined, ej:get({NotKeyForType(Type)}, Got))]
             end
             || Type <- [key, cert] ],
    lists:flatten(Tests).

assemble_client_pubkey_ejson_test_() ->
    [{"Handle client missing public key",
      fun() ->
              Client = #chef_client{name = <<"alice">>,
                                    admin = true,
                                    validator = false},
              {GotList} = chef_client:assemble_client_pubkey_ejson(Client),
              ExpectedData = [{<<"name">>, <<"alice">>},
                              {<<"pubkey">>, <<"">>},
                              {<<"pubkey_version">>, -1}],
              ?assertEqual(ExpectedData, GotList) end},
    {"Handle client w/public key",
     fun() ->
             Client = #chef_client{name = <<"bob">>,
                                   public_key = <<"-----BEGIN PUBLIC KEY">>},
             {GotList} = chef_client:assemble_client_pubkey_ejson(Client),
             ExpectedData = [{<<"name">>, <<"bob">>},
                             {<<"pubkey">>, <<"-----BEGIN PUBLIC KEY">>},
                             {<<"pubkey_version">>, 0}],
             ?assertEqual(ExpectedData, GotList) end}].

osc_assemble_client_ejson_test_() ->
    [{"obtain expected EJSON",
      fun() ->
              Client = #chef_client{name = <<"alice">>,
                                    admin = true,
                                    validator = false,
                                    public_key = public_key_data()},
              {GotList} = chef_client:osc_assemble_client_ejson(Client, ?OSC_ORG_NAME),
              ExpectedData = [{<<"json_class">>, <<"Chef::ApiClient">>},
                              {<<"chef_type">>, <<"client">>},
                              {<<"public_key">>, public_key_data()},
                              {<<"validator">>, false},
                              {<<"admin">>, true},
                              {<<"name">>, <<"alice">>}],
              ?assertEqual(lists:sort(ExpectedData), lists:sort(GotList))
      end},

     {"sets defaults if 'undefined' is encountered",
      fun() ->
              Client = #chef_client{},
              {GotList} = chef_client:osc_assemble_client_ejson(Client, ?OSC_ORG_NAME),
              ExpectedData = [{<<"json_class">>, <<"Chef::ApiClient">>},
                              {<<"chef_type">>, <<"client">>},
                              {<<"validator">>, false},
                              {<<"admin">>, false},
                              {<<"name">>, <<"">>}],
              ?assertEqual(lists:sort(ExpectedData), lists:sort(GotList))
      end
      }
    ].

osc_parse_binary_json_test_() ->
    [{"Can create with only URL name and has default values",
      fun() ->
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{}">>, <<"alice">>),
              ExpectedData = [{<<"json_class">>, <<"Chef::ApiClient">>},
                              {<<"chef_type">>, <<"client">>},
                              {<<"validator">>, false},
                              {<<"admin">>, false},
                              {<<"name">>, <<"alice">>}],
              {GotData} = Client,
              ?assertEqual(lists:sort(ExpectedData), lists:sort(GotData))
      end
     },

     {"Error thrown when missing both name and URL name",
      fun() ->
              Body = <<"{\"validator\":false}">>,
              ?assertThrow({both_missing, <<"name">>, <<"URL-NAME">>},
                           chef_client:osc_parse_binary_json(Body, undefined))
      end
     },

     {"Error thrown with bad name",
      fun() ->
              Body = <<"{\"name\":\"bad~name\"}">>,
              ?assertThrow({bad_client_name, <<"bad~name">>,
                            <<"Malformed client name.  Must be A-Z, a-z, 0-9, _, -, or .">>},
                           chef_client:osc_parse_binary_json(Body, <<"bad~name">>))
      end
     },

     {"Inherits values from current client",
      fun() ->
              CurClient = #chef_client{admin = true, validator = true,
                                       public_key = public_key_data()},
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{}">>, <<"alice">>, CurClient),
              ExpectedData = [{<<"json_class">>, <<"Chef::ApiClient">>},
                              {<<"chef_type">>, <<"client">>},
                              {<<"validator">>, true},
                              {<<"admin">>, true},
                              {<<"public_key">>, public_key_data()},
                              {<<"name">>, <<"alice">>}],
              {GotData} = Client,
              ?assertEqual(lists:sort(ExpectedData), lists:sort(GotData))
              
      end
     },

     {"Inherits values from current client but can override true to false",
      fun() ->
              %% override true with false
              CurClient = #chef_client{admin = true, validator = true,
                                       public_key = public_key_data()},
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{\"validator\":false, \"admin\":false}">>,
                                                           <<"alice">>, CurClient),
              ?assertEqual(false, ej:get({"admin"}, Client)),
              ?assertEqual(false, ej:get({"validator"}, Client))
      end
     },

     {"Inherits values from current client but can override false to true",
       fun() ->
               %% override false with true
               CurClient = #chef_client{admin = false, validator = false,
                                        public_key = public_key_data()},
               {ok, Client} = chef_client:osc_parse_binary_json(<<"{\"validator\":true, \"admin\":true}">>,
                                                            <<"alice">>, CurClient),
               ?assertEqual(true, ej:get({"admin"}, Client)),
               ?assertEqual(true, ej:get({"validator"}, Client))
       end
     },

     {"Inherits a certificate",
      fun() ->
              %% override true with false
              CurClient = #chef_client{admin = true, validator = true,
                                       public_key = cert_data()},
              {ok, Client} = chef_client:osc_parse_binary_json(<<"{\"validator\":false, \"admin\":false}">>,
                                                           <<"alice">>, CurClient),
              ?assertEqual(cert_data(), ej:get({"certificate"}, Client))
      end
     }

    ].


oc_parse_binary_json_test_() ->
    [{"Error thrown on mismatched names",
      fun() ->
          Body = <<"{\"name\":\"name\",\"clientname\":\"notname\"}">>,
          ?assertThrow({client_name_mismatch}, chef_client:oc_parse_binary_json(Body, <<"name">>))
      end
     },
     {"Can create with only name",
      fun() ->
          Body = <<"{\"name\":\"name\"}">>,
          {ok, Client} = chef_client:oc_parse_binary_json(Body, <<"name">>),
          Name = ej:get({<<"name">>}, Client),
          ClientName = ej:get({<<"clientname">>}, Client),
          ?assertEqual(Name, ClientName)
      end
     },
     {"Can create with only clientname",
      fun() ->
          Body = <<"{\"clientname\":\"name\"}">>,
          {ok, Client} = chef_client:oc_parse_binary_json(Body, <<"name">>),
          Name = ej:get({<<"name">>}, Client),
          ClientName = ej:get({<<"clientname">>}, Client),
          ?assertEqual(Name, ClientName)
      end
     },
     {"Error thrown with no name or clientname",
      fun() ->
          Body = <<"{\"validator\":false}">>,
          ?assertThrow({both_missing, <<"name">>, <<"clientname">>},
                       chef_client:oc_parse_binary_json(Body, undefined))
      end
     },
     {"Error thrown with bad name",
      fun() ->
          Body = <<"{\"name\":\"bad~name\"}">>,
          ?assertThrow({bad_client_name, <<"bad~name">>,
                        <<"Malformed client name.  Must be A-Z, a-z, 0-9, _, -, or .">>},
                       chef_client:oc_parse_binary_json(Body, <<"bad~name">>))
      end
     }
    ].

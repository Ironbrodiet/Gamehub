/*
This file is part of GameHub.
Copyright (C) 2018-2019 Anatoliy Kashkin

GameHub is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

GameHub is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GameHub.  If not, see <https://www.gnu.org/licenses/>.
*/

using Gee;

using GameHub.Data.DB;
using GameHub.Data.Runnables;
using GameHub.Utils;

namespace GameHub.Data.Sources.Humble
{
	public class Trove: Humble
	{
		public const string PAGE_URL = "https://humblebundle.com/api/v1/trove/chunk?property=start&direction=desc&index=%d";
		public const string SIGN_URL = "https://humblebundle.com/api/v1/user/download/sign";
		public const string FAKE_ORDER = "humble-trove";

		public override string id { get { return "humble-trove"; } }
		public override string name { get { return "Humble Trove"; } }
		public override string icon { get { return "source-humble-trove-symbolic"; } }

		public override bool enabled
		{
			get { return Settings.Auth.Humble.instance.enabled && Settings.Auth.Humble.instance.load_trove_games; }
			set { Settings.Auth.Humble.instance.load_trove_games = value; }
		}

		private ArrayList<Game> _games = new ArrayList<Game>(Game.is_equal);

		public override ArrayList<Game> games { get { return _games; } }

		public override async ArrayList<Game> load_games(Utils.FutureResult2<Game, bool>? game_loaded=null, Utils.Future? cache_loaded=null)
		{
			if(user_token == null || _games.size > 0)
			{
				return _games;
			}

			Utils.thread("HumbleTroveLoading", () => {
				_games.clear();

				var cached = Tables.Games.get_all(this);
				games_count = 0;
				if(cached.size > 0)
				{
					foreach(var g in cached)
					{
						if(g.platforms.size == 0) continue;
						if(!Settings.UI.Behavior.instance.merge_games || !Tables.Merges.is_game_merged(g))
						{
							_games.add(g);
							if(game_loaded != null)
							{
								game_loaded(g, true);
							}
						}
						games_count++;
					}
				}

				if(cache_loaded != null)
				{
					cache_loaded();
				}

				var headers = new HashMap<string, string>();
				headers["Cookie"] = escaped_cookie(user_token);

				var page = 0;

				while(true)
				{
					var root_node = Parser.parse_remote_json_file(Trove.PAGE_URL.printf(page), "GET", null, headers);
					var root = root_node != null && root_node.get_node_type() == Json.NodeType.ARRAY ? root_node.get_array() : null;

					if(root == null || root.get_length() == 0) break;

					debug("[Trove] Loading games: page %d", page + 1);

					root.foreach_element((array, index, node) => {
						var obj = node.get_object();
						var key = obj.get_string_member("machine_name");

						var downloads = obj.get_object_member("downloads");
						downloads.foreach_member((downloads_obj, dl_os, dl_node) => {
							var dl_obj = dl_node.get_object();
							var dl_name = dl_obj.get_string_member("machine_name");
							var dl_id = dl_obj.get_object_member("url").get_string_member("web");
							dl_obj.set_string_member("download_identifier", dl_id);
							dl_obj.get_object_member("url").set_string_member("web", "humble-trove-unsigned://" + dl_name + "/_gh_dl_/" + dl_id);
						});

						var game = new HumbleGame(this, Trove.FAKE_ORDER, node);

						if(game.platforms.size == 0) return;
						bool is_new_game = !_games.contains(game);
						if(is_new_game && (!Settings.UI.Behavior.instance.merge_games || !Tables.Merges.is_game_merged(game)))
						{
							_games.add(game);
							if(game_loaded != null)
							{
								game_loaded(game, false);
							}
						}
						if(is_new_game)
						{
							games_count++;
							game.save();
						}
					});

					page++;
				}

				Idle.add(load_games.callback);
			});

			yield;

			return _games;
		}

		public static async string? sign_url(string machine_name, string filename, string humble_token)
		{
			var headers = new HashMap<string, string>();
			headers["Cookie"] = escaped_cookie(humble_token);

			var data = new HashMap<string, string>();
			data["machine_name"] = machine_name;
			data["filename"] = filename;

			var signed_node = yield Parser.parse_remote_json_file_async(Trove.SIGN_URL, "POST", null, headers, data);
			var signed = signed_node != null && signed_node.get_node_type() == Json.NodeType.OBJECT ? signed_node.get_object() : null;

			var signed_url = signed != null && signed.has_member("signed_url") ? signed.get_string_member("signed_url") : null;

			if(GameHub.Application.log_verbose)
			{
				debug("[Trove.sign_url] '%s':'%s' -> '%s'", machine_name, filename, signed_url);
			}

			return signed_url;
		}
	}
}

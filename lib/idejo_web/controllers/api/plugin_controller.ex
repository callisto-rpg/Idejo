# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.PluginController do
  @moduledoc """
  Plugins' blocks (AP-12): `params` as the plugin dialog sends them, under the author's
  message (`message_id`) or starting it (`Plugins.post/5`), with the same refusals as the
  web's plugin form; and the `!forum` plugin's directory search.
  """
  use IdejoWeb.Api.Controller

  alias Idejo.Plugins

  def create(conn, %{"id" => id, "command" => command} = params) do
    plugin_params = if is_map(params["params"]), do: params["params"], else: %{}

    with {:ok, topic} <- readable_topic(conn, id) do
      result =
        case string(params, "message_id") do
          nil ->
            Plugins.post(user(conn), topic, command, plugin_params, string(params, "reply_to"))

          message_id ->
            Plugins.attach(user(conn), message_id, command, plugin_params)
        end

      with {:ok, message} <- result, do: json(conn, Api.message(user(conn), message))
    end
  end

  def forums(conn, %{"id" => id, "command" => command} = params) do
    with {:ok, topic} <- readable_topic(conn, id),
         {:ok, %{block: "forum"} = definition} <- Plugins.may_use(user(conn), topic, command) do
      send_list(conn, Plugins.search_forums(definition, string(params, "q") || ""))
    else
      {:ok, _other} -> {:error, :not_found}
      error -> error
    end
  end
end

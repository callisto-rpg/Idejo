# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.ServerController do
  @moduledoc """
  The server as the app needs it (AP-12): name, About and Rules, self-select roles, the
  settings that change how a client behaves, the server's own emoji and active plugins;
  search, suggestions, emoji and GIFs.
  """
  use IdejoWeb.Api.Controller

  alias Idejo.{Access, Emoji, Gifs, Plugins, Search, Settings, Suggestions, Uploads}
  alias Idejo.Messages

  def show(conn, _params) do
    json(conn, %{
      "name" => Settings.get(:server_name),
      "url" => Api.base() <> "/",
      "logo_url" => Api.base() <> "/logo",
      "about_md" => Settings.get(:server_about),
      "rules_md" => Settings.get(:server_rules),
      "privacy_md" => Settings.get(:privacy_notice),
      "roles" => Enum.map(Access.self_select_roles(), &role/1),
      "settings" => %{
        "gm_window_seconds" => Settings.get(:gm_window_seconds),
        "gm_unanswered_seconds" => Messages.unanswered_seconds(),
        "gm_early_reply" => Messages.early_reply_allowed?(),
        "gifs" => Gifs.enabled?(),
        "push" => Idejo.Push.enabled?(),
        "upload_types" => Enum.map(Uploads.extensions(), &String.trim_leading(&1, ".")),
        "upload_max_bytes" => Uploads.max_bytes(),
        "registration" => Settings.get(:registration_mode)
      },
      "emoji" => server_emoji(),
      "default_reactions" => Enum.map(Emoji.defaults(), &emoji/1),
      "plugins" => Enum.map(Plugins.active(), fn {_command, plugin} -> plugin(plugin) end)
    })
  end

  defp role(role),
    do: %{
      "id" => role.id,
      "name" => role.name,
      "colour" => role.colour,
      "slug" => Access.role_slug(role)
    }

  defp server_emoji do
    case Emoji.groups() do
      [{_server, emoji} | _] -> Enum.map(emoji, &emoji/1)
      [] -> []
    end
  end

  defp emoji(emoji),
    do: %{"name" => emoji.name, "char" => emoji.char, "image_url" => Api.absolute(emoji.src)}

  defp plugin(%{definition: definition}) do
    %{
      "command" => definition.command,
      "name" => definition.name,
      "description" => definition.description,
      "argument" => definition.argument,
      "block" => definition.block
    }
  end

  def emoji(conn, params) do
    emoji =
      for {_group, list} <- Emoji.groups(string(params, "q") || ""), emoji <- list, do: emoji

    send_list(conn, emoji |> Enum.take(200) |> Enum.map(&emoji/1))
  end

  # KLIPY's terms (steward decision, 2026-11-03): the client calls the provider and loads
  # its media itself, never through idejo; so the app gets the browser's configuration.
  def gifs(conn, _params) do
    json(conn, %{"enabled" => Gifs.enabled?(), "config" => Gifs.client_config()})
  end

  def search(conn, params) do
    with page when is_integer(page) <- page_number(params, :search) || {:error, :bad_request},
         {:ok, category} <- search_category(conn, params["category_id"]) do
      opts =
        [page: page, per_page: limit(params)] ++ if(category, do: [category: category], else: [])

      {results, more?} = Search.search(user(conn), string(params, "q") || "", opts)
      {next, prev} = page_cursors(:search, page, more?)
      send_page(conn, Enum.map(results, &hit/1), next, prev)
    end
  end

  defp search_category(_conn, blank) when blank in [nil, ""], do: {:ok, nil}

  defp search_category(conn, id) when is_binary(id) do
    case Enum.find(Idejo.Forum.list_viewable_categories(user(conn)), &(&1.id == id)) do
      nil -> {:error, :not_found}
      category -> {:ok, category}
    end
  end

  defp search_category(_conn, _id), do: {:error, :bad_request}

  defp hit(%{message: message, excerpt: segments}) do
    %{
      "message_id" => message.id,
      "topic_id" => message.topic_id,
      "topic_title" => message.topic.title,
      "category_id" => message.topic.category_id,
      "author_name" => Messages.author_name(message),
      "url" => Api.base() <> "/m/" <> message.id,
      "opened_at" => Api.time(message.opened_at),
      "excerpt" =>
        Enum.map(segments, fn {kind, text} -> %{"text" => text, "match" => kind == :match} end)
    }
  end

  def suggest(conn, params) do
    case Suggestions.kind(string(params, "sigil") || "") do
      nil ->
        {:error, :bad_request}

      kind ->
        opts = if is_binary(params["topic_id"]), do: [topic_id: params["topic_id"]], else: []

        items =
          user(conn)
          |> Suggestions.suggest(kind, string(params, "q") || "", opts)
          |> Enum.map(&suggestion(kind, &1))

        send_list(conn, items)
    end
  end

  defp suggestion(:user, user),
    do: %{
      "kind" => "user",
      "insert" => user.username,
      "label" => user.display_name,
      "id" => user.id
    }

  defp suggestion(:role, role),
    do: %{
      "kind" => "role",
      "insert" => Access.role_slug(role),
      "label" => role.name,
      "id" => role.id
    }

  defp suggestion(:topic, topic),
    do: %{"kind" => "topic", "insert" => topic.slug, "label" => topic.title, "id" => topic.id}

  defp suggestion(:category, category),
    do: %{
      "kind" => "category",
      "insert" => category.slug,
      "label" => category.name,
      "id" => category.id
    }

  defp suggestion(:tag, tag),
    do: %{"kind" => "tag", "insert" => tag.slug, "label" => tag.name, "id" => tag.id}

  defp suggestion(:forum, forum),
    do: %{"kind" => "forum", "insert" => forum.slug, "label" => forum.name, "id" => forum.url}
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Inbox.RemoteTopic do
  @moduledoc """
  A topic another forum of the group sent the inbox (steward request, 2026-11-10; its
  `GET /community/topics`), turned into idejo's own structs, so the inbox draws it with the
  same topic rows as any forum (`IdejoWeb.TopicComponents.topic_row/1` with `base:`, the
  forum's address every link and picture of the row starts with). Nothing is stored.

  `from_json/3` → `%{topic:, preview:, unread:, mentions:, reactions:, base:, forum:}`
  (`forum`: `name`, `url`, `host`, `logo`), or nil for something unreadable. A forum
  before the full row (0.3.4) sends no `preview`: compact only; before 0.3.6, no
  `mentions` or `reactions` (0).
  """

  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Topic, TopicIcon}
  alias Idejo.Messages.Message
  alias Idejo.Uploads.Upload

  @doc "The topic, its preview and unread count, from a forum's JSON."
  @spec from_json(map(), String.t(), String.t() | nil) :: map() | nil
  def from_json(%{"id" => id, "title" => title} = json, url, forum_name)
      when is_binary(id) and is_binary(title) do
    at = time(json["last_activity_at"])
    base = String.trim_trailing(url, "/")

    %{
      topic: %Topic{
        id: id,
        title: title,
        slug: text(json["slug"]) || "topic",
        state: text(json["state"]) || "open",
        pinned: json["pinned"] == true,
        topical: json["topical"] == true,
        message_count: integer(json["message_count"]),
        last_activity_at: at,
        category: category(json["category"]),
        category_id: get_in(json, ["category", "id"]),
        author: user(json["author"]),
        icon: icon(json["icon_path"]),
        icon_id: nil,
        tags: []
      },
      preview: preview(json["preview"]),
      unread: if(integer(json["unread"]) > 0, do: integer(json["unread"])),
      # The topic card's activity (steward request, 2026-11-12); 0 from forums before it.
      mentions: integer(json["mentions"]),
      reactions: integer(json["reactions"]),
      base: base,
      forum: %{
        name: forum_name || URI.parse(url).host,
        url: url,
        host: URI.parse(url).host,
        # 0.2.9's /logo: the forum's own logo, or idejo's small one.
        logo: base <> "/logo"
      }
    }
  end

  def from_json(_json, _url, _forum), do: nil

  defp category(%{"name" => name} = json) when is_binary(name) do
    %Category{
      id: json["id"] || name,
      name: name,
      slug: text(json["slug"]) || "",
      colour: colour(json["colour"]),
      icon: text(json["icon"])
    }
  end

  defp category(_json), do: nil

  defp user(%{"display_name" => name} = json) when is_binary(name) and name != "" do
    %User{
      display_name: name,
      username: text(json["username"]),
      avatar_id: uuid(json["avatar_id"]),
      avatar_dark_id: uuid(json["avatar_dark_id"]),
      status: if(json["status"] == "system", do: "system", else: "active"),
      user_tag: nil
    }
  end

  defp user(_json), do: %User{display_name: "?", status: "active"}

  defp icon("/uploads/" <> path) when byte_size(path) < 80,
    do: %TopicIcon{upload: %Upload{path: path}}

  defp icon(_path), do: nil

  defp preview(%{} = json) do
    people = for p <- list(json["participants"]), do: user(p)

    %{
      first: message(json["first"]),
      images: for("/uploads/" <> _ = src <- list(json["images"]), do: src),
      latest: list(json["latest"]) |> Enum.map(&message/1) |> Enum.reject(&is_nil/1),
      participants: people,
      participant_count: max(integer(json["participant_count"]), length(people))
    }
  end

  defp preview(_json), do: nil

  defp message(%{"body_html" => html} = json) when is_binary(html) do
    %Message{
      id: json["id"],
      body_html: MDEx.safe_html(html, escape: [:curly_braces_in_code]),
      anonymous: json["anonymous"] == true,
      spoiler: json["spoiler"] == true,
      spoiler_label: text(json["spoiler_label"]),
      opened_at: time(json["opened_at"]),
      author: user(json["author"])
    }
  end

  defp message(_json), do: nil

  defp time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> at
      _ -> DateTime.utc_now()
    end
  end

  defp time(_value), do: DateTime.utc_now()

  defp list(value) when is_list(value), do: value
  defp list(_value), do: []

  defp integer(n) when is_integer(n) and n >= 0, do: n
  defp integer(_n), do: 0

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil

  defp colour("#" <> hex = value) when byte_size(hex) == 6, do: value
  defp colour(_value), do: nil

  defp uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp uuid(_value), do: nil
end

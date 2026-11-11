# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.TopicController do
  @moduledoc """
  Topics (AP-12, AP-14, AP-16): lists (active, by tag, Unread), one topic, its title and
  tags, following, muting, the read position, its messages a window at a time (the same
  windows as the web, `Idejo.Forum.TopicWindow`), its changes since a cursor, and the
  composer's commands.

  Reading a topic's messages marks nothing read: the app says how far its reader got with
  `PUT /topics/{id}/read`.
  """
  use IdejoWeb.Api.Controller

  alias Idejo.Api.Changes
  alias Idejo.Forum
  alias Idejo.Forum.{Tags, TopicWindow}
  alias Idejo.Messages.Commands
  alias Idejo.Reading

  def active(conn, params) do
    topics = Forum.list_active_topics(user(conn), limit(params))
    send_list(conn, Api.topics(user(conn), topics))
  end

  def tagged(conn, params) do
    slugs =
      (string(params, "tags") || "") |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    tags = Enum.filter(Tags.list_viewable_tags(user(conn)), &(&1.slug in slugs))
    match = if params["operator"] == "or", do: :any, else: :all
    list = {:tags, Enum.sort(slugs), match}

    with page when is_integer(page) <- page_number(params, list) || {:error, :bad_request} do
      {topics, more?} =
        Tags.list_tagged_topics(user(conn), tags,
          match: match,
          page: page,
          per_page: limit(params)
        )

      {next, prev} = page_cursors(list, page, more?)
      send_page(conn, Api.topics(user(conn), topics), next, prev)
    end
  end

  def tags(conn, _params),
    do: send_list(conn, Enum.map(Tags.list_viewable_tags(user(conn)), &Api.tag/1))

  def unread(conn, params) do
    user = user(conn)

    with page when is_integer(page) <- page_number(params, :unread) || {:error, :bad_request} do
      following = if page == 1, do: Reading.list_unread_followed_topics(user), else: []

      {others, more?} =
        Reading.list_unread_topics(user, following: false, page: page, per_page: limit(params))

      {next, prev} = page_cursors(:unread, page, more?)
      counter = Reading.for_you(user)

      json(conn, %{
        "following" => counted(user, following),
        "others" => %{
          "data" => counted(user, others),
          "next_cursor" => next,
          "prev_cursor" => prev
        },
        "counter" => %{
          "count" => counter.count,
          "level" => counter.level && Atom.to_string(counter.level)
        }
      })
    end
  end

  defp counted(user, rows) do
    unread = Map.new(rows, fn {topic, count} -> {topic.id, count} end)
    Api.topics(user, Enum.map(rows, &elem(&1, 0)), unread: unread)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, topic} <- readable_topic(conn, id), do: json(conn, Api.topic(user(conn), topic))
  end

  @doc "`title` (`Forum.rename_topic/4`) and `tag_ids` (`Forum.set_topic_tags/4`), with `reason`."
  def update(conn, %{"id" => id} = params) do
    user = user(conn)

    with {:ok, topic} <- viewable_topic(conn, id),
         {:ok, topic} <- maybe_rename(user, topic, params),
         {:ok, topic} <- maybe_tags(user, topic, params) do
      json(conn, Api.topic(user, Forum.get_viewable_topic(user, topic.id)))
    end
  end

  defp maybe_rename(user, topic, %{"title" => title} = params) when is_binary(title),
    do: Forum.rename_topic(user, topic, title, string(params, "reason"))

  defp maybe_rename(_user, topic, _params), do: {:ok, topic}

  defp maybe_tags(user, topic, %{"tag_ids" => ids} = params) when is_list(ids),
    do: Forum.set_topic_tags(user, topic, ids, string(params, "reason"))

  defp maybe_tags(_user, topic, _params), do: {:ok, topic}

  def follow(conn, %{"id" => id}), do: act(conn, :follow, id)
  def unfollow(conn, %{"id" => id}), do: act(conn, :unfollow, id)
  def mute(conn, %{"id" => id}), do: act(conn, :mute, id)
  def unmute(conn, %{"id" => id}), do: act(conn, :follow, id)
  def mark_unread(conn, %{"id" => id}), do: act(conn, :mark_unread, id)

  defp act(conn, action, id) do
    with {:ok, topic} <- Reading.act_on_topic(user(conn), action, id),
         do: json(conn, Api.topic(user(conn), topic))
  end

  @doc "`message_id`: how far the reader got; without one, the whole topic is read."
  def read(conn, %{"id" => id} = params) do
    user = user(conn)

    with {:ok, topic} <- readable_topic(conn, id),
         :ok <- read_to(user, topic, params["message_id"]) do
      json(conn, Api.topic(user, topic))
    end
  end

  defp read_to(user, topic, nil), do: Reading.mark_read(user, topic)
  defp read_to(user, topic, message_id), do: Reading.mark_read_to(user, topic, message_id)

  def messages(conn, %{"id" => id} = params) do
    with {:ok, topic} <- readable_topic(conn, id), do: window(conn, topic, params)
  end

  @doc """
  A window of a topic's or conversation's messages: the end; `around` a message; the first
  unread one (`first_unread=true`); or a page from a cursor. `first_message` is the topic's
  opening message, always there (none in a private conversation), as the web pins it.
  """
  def window(conn, topic, params) do
    user = user(conn)
    first_unread = Reading.first_unread(user, topic)

    with {:ok, messages} <- messages_at(topic, params, first_unread) do
      first = TopicWindow.first(topic)
      latest = TopicWindow.latest(topic)

      json(conn, %{
        "data" => Api.messages(user, topic, messages),
        "first_message" => opening(user, topic, first),
        "first_unread" => unread_mark(first_unread),
        "next_cursor" => edge_cursor(topic, :after, List.last(messages), latest && latest.id),
        "prev_cursor" => edge_cursor(topic, :before, List.first(messages), first && first.id),
        "cursor" => Changes.cursor(topic),
        "total" => TopicWindow.count(topic)
      })
    end
  end

  defp messages_at(topic, params, first_unread) do
    limit = limit(params)

    case read_cursor(params, {:messages, topic.id}) do
      {:ok, {:before, id}} -> at(topic, id, &TopicWindow.before(topic, &1, limit))
      {:ok, {:after, id}} -> at(topic, id, &TopicWindow.next(topic, &1, limit))
      :error -> {:error, :bad_request}
      :none -> landing(nil, topic, params, first_unread, TopicWindow.sizes(), limit)
    end
  end

  # The opening message, pinned on top as the web does; none in a private conversation.
  defp opening(_user, %{private: true}, _first), do: nil
  defp opening(_user, _topic, nil), do: nil
  defp opening(user, _topic, first), do: Api.message(user, first)

  defp unread_mark(nil), do: nil
  defp unread_mark(%{id: id, count: count}), do: %{"message_id" => id, "count" => count}

  defp landing(_user, topic, params, first_unread, sizes, limit) do
    cond do
      is_binary(params["around"]) ->
        at(topic, params["around"], &TopicWindow.around(topic, &1, sizes.before, sizes.after))

      boolean(params, "first_unread") and first_unread != nil ->
        at(topic, first_unread.id, &TopicWindow.around(topic, &1, sizes.before, sizes.after))

      true ->
        {:ok, TopicWindow.last(topic, limit)}
    end
  end

  defp at(topic, message_id, fun) when is_binary(message_id) do
    case Forum.get_topic_message(topic, message_id) do
      nil -> {:error, :not_found}
      message -> {:ok, fun.(message)}
    end
  end

  defp at(_topic, _message_id, _fun), do: {:error, :not_found}

  # No cursor past the topic's ends.
  defp edge_cursor(_topic, _side, nil, _edge_id), do: nil
  defp edge_cursor(_topic, _side, %{id: id}, id), do: nil

  defp edge_cursor(topic, side, message, _edge_id),
    do: cursor({:messages, topic.id}, {side, message.id})

  def changes(conn, %{"id" => id} = params) do
    with {:ok, topic} <- readable_topic(conn, id), do: changes_of(conn, topic, params)
  end

  @doc "Every message change after `since` (AP-16), oldest first, a page at a time."
  def changes_of(conn, topic, params) do
    case Integer.parse(to_string(params["since"] || "0")) do
      {since, ""} when since >= 0 ->
        with {:ok, messages, cursor, more?} <- Changes.since(topic, since, limit(params)) do
          json(conn, %{
            "data" => Api.messages(user(conn), topic, messages),
            "cursor" => cursor,
            "more" => more?,
            "topic" => Api.topic(user(conn), topic)
          })
        end

      _ ->
        {:error, :bad_request}
    end
  end

  def commands(conn, %{"id" => id}) do
    with {:ok, topic} <- readable_topic(conn, id) do
      send_list(conn, Enum.map(Commands.available(user(conn), topic), &command/1))
    end
  end

  defp command(command) do
    command
    |> Map.new(fn {key, value} -> {Atom.to_string(key), string_value(value)} end)
    |> Map.take(~w(name kind sender argument block))
  end

  defp string_value(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp string_value(value), do: value
end

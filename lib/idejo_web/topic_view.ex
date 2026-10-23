# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicView do
  @moduledoc """
  The topic lists' view on the home and category pages (steward decision, 2026-10-23):
  `:compact` (the default) or `:expanded`, whose cards also show the opening message, an
  image from it, the latest messages and who wrote there (`Idejo.Forum.topic_previews/1`).

  The toggle is two links (`?view=compact`, `?view=expanded`), so it works without
  JavaScript; the choice is remembered in the session for the next pages.
  """
  import Plug.Conn

  @views %{"compact" => :compact, "expanded" => :expanded}

  @doc "The view asked for, or the one remembered (`:compact` at first); remembers a new one."
  @spec choose(Plug.Conn.t(), map()) :: {Plug.Conn.t(), :compact | :expanded}
  def choose(conn, %{"view" => view}) when is_map_key(@views, view),
    do: {put_session(conn, :topic_view, view), @views[view]}

  def choose(conn, _params), do: {conn, Map.get(@views, get_session(conn, :topic_view), :compact)}

  @doc "The previews an expanded list needs, or none for a compact one."
  @spec previews(:compact | :expanded, [map()]) :: map()
  def previews(:expanded, topics), do: Idejo.Forum.topic_previews(Enum.map(topics, & &1.id))
  def previews(:compact, _topics), do: %{}
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SidebarController do
  @moduledoc """
  The sidebar alone (`IdejoWeb.Layouts.sidebar/1`) and the header's Unread link with its
  count (`Layouts.unread_link/1`), at `/sidebar` for signed-in users: the `Notifier` hook
  fetches them when a notification arrives and on a schedule (assets/js/notifier.js), so
  the followed topics, their dots and the count stay current without a page load (steward
  decision, 2026-10-23).
  `?category=` marks the category the page shows and `?topic=` the topic, as the page itself
  does (a topic the user may not view is ignored).
  """
  use IdejoWeb, :controller

  def show(conn, params) do
    current =
      case Ecto.UUID.cast(params["category"] || "") do
        {:ok, id} -> %{id: id}
        :error -> nil
      end

    user = conn.assigns.current_scope.user

    topic =
      case Ecto.UUID.cast(params["topic"] || "") do
        {:ok, id} -> Idejo.Forum.get_viewable_topic(user, id)
        :error -> nil
      end

    conn
    |> put_root_layout(false)
    |> put_resp_header("cache-control", "no-store")
    |> render(:show, user: user, current: current, topic: topic)
  end
end

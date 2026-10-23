# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SidebarController do
  @moduledoc """
  The sidebar alone (`IdejoWeb.Layouts.sidebar/1`), at `/sidebar` for signed-in users: the
  `Notifier` hook fetches it when a notification arrives, and every minute, so the followed
  topics and their dots stay current without a page load (steward decision, 2026-10-23).
  `?category=` marks the category the page shows, as the page itself does.
  """
  use IdejoWeb, :controller

  def show(conn, params) do
    current =
      case Ecto.UUID.cast(params["category"] || "") do
        {:ok, id} -> %{id: id}
        :error -> nil
      end

    conn
    |> put_root_layout(false)
    |> put_resp_header("cache-control", "no-store")
    |> render(:show, user: conn.assigns.current_scope.user, current: current)
  end
end

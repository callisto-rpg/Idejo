# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.NotificationController do
  @moduledoc """
  The Notifications screen (MVP §5, NO-01) at `/notifications`, for signed-in users: mentions,
  replies and new messages in followed topics, unread first, 30 a page. Opening one
  (`/notifications/{id}`) marks it read and goes to the message; "Mark all read" posts to
  `/notifications/read`. Plain pages and forms, no JavaScript needed.
  """
  use IdejoWeb, :controller

  alias Idejo.Notifications

  def index(conn, params) do
    page = page(params)
    {notifications, more?} = Notifications.list(conn.assigns.current_scope.user, page: page)

    render(conn, :index,
      page_title: gettext("Notifications"),
      notifications: notifications,
      page: page,
      more?: more?
    )
  end

  def show(conn, %{"id" => id}) do
    case Notifications.open(conn.assigns.current_scope.user, id) do
      nil -> raise Ecto.NoResultsError, queryable: Idejo.Notifications.Notification
      notification -> redirect(conn, to: ~p"/m/#{notification.message_id}")
    end
  end

  def read_all(conn, _params) do
    :ok = Notifications.mark_all_read(conn.assigns.current_scope.user)
    redirect(conn, to: ~p"/notifications")
  end

  defp page(%{"page" => page}) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page(_params), do: 1
end

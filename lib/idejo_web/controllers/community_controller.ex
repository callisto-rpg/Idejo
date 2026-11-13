# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CommunityController do
  @moduledoc """
  The community menu (steward decision, 2026-11-06): the signed-in member's other
  communities as JSON, `{"communities": [{"name", "url"}]}`, for `assets/js/community_menu.js`
  (`Idejo.Community.communities/1`). Empty for visitors and on a standalone install. Never
  cached by the browser: it is about the person.

  `activity/2` (`/community/activity`, steward request, 2026-11-13): what is new for them in
  the topics they follow in their other forums, `{"unread", "mentions"}`
  (`Idejo.Community.Chat.activity/1`), for the dot on the forum's logo; zeros otherwise.
  """
  use IdejoWeb, :controller

  alias Idejo.Community.Chat

  def index(conn, _params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> json(%{communities: Idejo.Community.communities(user)})
  end

  def activity(conn, _params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> json(Chat.activity(user))
  end
end

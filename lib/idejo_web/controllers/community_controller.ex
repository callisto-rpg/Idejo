# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CommunityController do
  @moduledoc """
  The community menu (steward decision, 2026-11-06): the signed-in member's other
  communities as JSON, `{"communities": [{"name", "url"}]}`, for `assets/js/community_menu.js`
  (`Idejo.Community.communities/1`). Empty for visitors and on a standalone install. Never
  cached by the browser: it is about the person.
  """
  use IdejoWeb, :controller

  def index(conn, _params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> json(%{communities: Idejo.Community.communities(user)})
  end
end

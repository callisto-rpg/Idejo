# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ModerationController do
  @moduledoc """
  The Moderation screen (MVP §5). `/moderation/log` is the moderation log (MO-03): every
  moderator action in the categories the viewer moderates (all of them for owners and
  administrators), newest first, 30 a page. Only for moderators; anyone else gets not found.
  """
  use IdejoWeb, :controller

  alias Idejo.Moderation

  def log(conn, params) do
    user = conn.assigns.current_scope.user

    if Moderation.moderator?(user) do
      page = page(params)
      {entries, more?} = Moderation.list(user, page: page)

      render(conn, :log,
        page_title: gettext("Moderation log"),
        entries: entries,
        page: page,
        more?: more?
      )
    else
      raise Ecto.NoResultsError, queryable: Idejo.Moderation.Action
    end
  end

  defp page(%{"page" => page}) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page(_params), do: 1
end

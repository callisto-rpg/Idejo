# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.GuestNoticeController do
  @moduledoc """
  The card over the home page for visitors who are not signed in (steward decision,
  2026-10-24; `PageController`): "Continue without signing in" posts here, a plain form, so
  it works without JavaScript. The choice is kept in the session, so the card does not come
  back for the rest of the visit.
  """
  use IdejoWeb, :controller

  @doc "The session key that hides the card."
  def session_key, do: :guest_notice_dismissed

  def dismiss(conn, _params) do
    conn
    |> put_session(session_key(), true)
    |> redirect(to: ~p"/")
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.IntroController do
  @moduledoc """
  The getting-started card's buttons (steward request, 2026-11-09): "Close" until the next
  sign-in, "Close and hide this in the future" for good (`Idejo.Accounts.close_intro/2`).
  A plain form, then back to the page it was on.
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts

  def update(conn, params) do
    {:ok, _user} =
      Accounts.close_intro(conn.assigns.current_scope.user, hide: params["choice"] == "hide")

    redirect(conn, to: IdejoWeb.ReturnBack.path(conn, params) || ~p"/")
  end
end

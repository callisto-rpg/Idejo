# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Unavailable do
  @moduledoc """
  What a link to a topic, message or category the reader may not view leads to (steward
  decision, 2026-10-24), the same whether it does not exist, was deleted or is in a category
  they may not view, so its existence is not given away (AC-05):

    * a visitor goes to the sign-in page (which links to sign-up), and signing in or up
      leads back to the link;
    * a signed-in user goes to the home page, which shows the "Unavailable" dialog once
      (the `:unavailable` flash, `"topic"` or `"category"`, read by `PageHTML`).
  """
  use IdejoWeb, :verified_routes
  use Gettext, backend: IdejoWeb.Gettext

  import Plug.Conn, only: [put_session: 3]
  import Phoenix.Controller

  @doc "Sends `conn` on as above; `kind` is `:topic` (messages too) or `:category`."
  def redirect_away(conn, kind) when kind in [:topic, :category] do
    case conn.assigns.current_scope do
      %{user: %{}} ->
        conn
        |> put_flash(:unavailable, Atom.to_string(kind))
        |> redirect(to: ~p"/")

      _ ->
        conn
        |> put_session(:user_return_to, current_path(conn))
        |> put_flash(:error, gettext("You must sign in to access this page."))
        |> redirect(to: ~p"/users/sign-in")
    end
  end

  @doc "The dialog's text for the `:unavailable` flash."
  def message("category"),
    do:
      gettext(
        "The category doesn't exist, was deleted, or you do not have permission to view it."
      )

  def message(_topic),
    do: gettext("The topic doesn't exist, was deleted, or you do not have permission to view it.")
end

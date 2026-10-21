# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserController do
  @moduledoc """
  A user's URI, `/u/{id}` (FD-01), as a page: the user card an @mention leads to (TP-10).
  Public and server-rendered, so a mention works without JavaScript too; with it, a topic
  opens the same card in a dialog instead.
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts
  alias IdejoWeb.UserComponents

  def show(conn, %{"id" => id}) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = user <- Accounts.get_user(id) do
      viewer = conn.assigns.current_scope && conn.assigns.current_scope.user

      # MO-02: server moderators get the "User actions" on the card.
      render(conn, :show,
        card: UserComponents.card_data(user, viewer),
        page_title: user.display_name
      )
    else
      _ -> raise Ecto.NoResultsError, queryable: Idejo.Accounts.User
    end
  end
end

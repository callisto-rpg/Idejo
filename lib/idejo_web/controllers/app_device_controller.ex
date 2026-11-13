# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AppDeviceController do
  @moduledoc """
  "Remove" under "Apps and devices" in Profile and account (AP-09; steward decision,
  2026-11-10): signs one of the user's devices out of the official app, a plain form that
  works without JavaScript. Its sockets close and its push registrations go with it.
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts.ApiTokens

  def delete(conn, %{"id" => id}) do
    conn =
      case ApiTokens.revoke(conn.assigns.current_scope.user, id) do
        :ok ->
          put_flash(conn, :info, gettext("The device was signed out of the idejo app."))

        {:error, :not_found} ->
          put_flash(conn, :error, gettext("This device was already signed out."))
      end

    redirect(conn, to: IdejoWeb.UserSettingsLive.path("account", "apps-section"))
  end
end

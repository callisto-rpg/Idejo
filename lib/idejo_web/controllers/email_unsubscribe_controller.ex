# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.EmailUnsubscribeController do
  @moduledoc """
  The email summary's unsubscribe link (NO-04; steward decision, 2026-10-23). The link opens
  a page with one button; mail programs that offer "Unsubscribe" post to the same address
  (`List-Unsubscribe-Post`, RFC 8058), which is outside the session and CSRF checks: the
  token in it is what allows it. Either way every summary is turned off
  (`Idejo.Notifications.Digest.unsubscribe/1`).
  """
  use IdejoWeb, :controller

  alias Idejo.Notifications.Digest

  def show(conn, %{"token" => token} = params) do
    render(conn, :show,
      page_title: gettext("Email notifications"),
      token: token,
      done?: params["done"] == "1"
    )
  end

  def create(conn, %{"token" => token}) do
    case {Digest.unsubscribe(token), conn.body_params} do
      {:error, _} ->
        conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not found")

      # A mail program's one-click unsubscribe.
      {:ok, %{"List-Unsubscribe" => "One-Click"}} ->
        conn |> put_resp_content_type("text/plain") |> send_resp(200, "Unsubscribed")

      {:ok, _} ->
        redirect(conn, to: ~p"/email/unsubscribe/#{token}?done=1")
    end
  end
end

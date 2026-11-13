# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.IdRegistrationController do
  @moduledoc """
  AC-09 (steward decisions, 2026-11-06): `GET /.well-known/idejo-id-registration`, the proof
  an idejo ID registry fetches while an administrator connects this server
  (`Idejo.Accounts.OIDCRegistry`): plain text for ten minutes, else 404. No session.
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts.OIDCRegistry

  def show(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case OIDCRegistry.proof() do
      nil -> send_resp(conn, 404, "")
      proof -> conn |> put_resp_content_type("text/plain") |> send_resp(200, proof)
    end
  end
end

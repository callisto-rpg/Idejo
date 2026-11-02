# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.HealthController do
  @moduledoc """
  `GET /health` (AD-15): `Idejo.Health.report/1` as JSON, 200 when every check is ok, else
  503. Routed outside the browser pipeline: no session, no CSRF, no sign-in, no layout, no
  setup redirect, no cookie; the endpoint's rate limit (SP-05) still counts it.
  """
  use IdejoWeb, :controller

  def show(conn, _params) do
    # Tests point the checks elsewhere through the conn; requests cannot set it.
    report = Idejo.Health.report(conn.private[:idejo_health] || [])

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(if report.status == "ok", do: 200, else: 503)
    |> json(report)
  end
end

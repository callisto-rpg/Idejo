# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.OpenApiController do
  @moduledoc "`GET /api/v1/openapi.json` (AP-01): the document, public, no token needed."
  use IdejoWeb.Api.Controller

  alias IdejoWeb.Api.OpenApi

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=300")
    |> json(OpenApi.document())
  end
end

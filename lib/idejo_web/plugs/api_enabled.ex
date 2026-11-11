# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.ApiEnabled do
  @moduledoc """
  AP-20 (steward decision, 2026-11-10): while "API and mobile app" is off in Admin →
  Settings, everything under `/api` and the app's authorize page answer 404, as if they
  did not exist. Tokens are kept, and work again once it is on.
  """
  @behaviour Plug

  alias Idejo.Accounts.ApiTokens
  alias IdejoWeb.Api.Errors

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    cond do
      ApiTokens.enabled?() -> conn
      opts[:html] -> conn |> Phoenix.Controller.put_view(IdejoWeb.ErrorHTML) |> not_found_html()
      true -> Errors.send_error(conn, :not_found)
    end
  end

  defp not_found_html(conn) do
    conn
    |> Plug.Conn.put_status(404)
    |> Phoenix.Controller.put_format("html")
    |> Phoenix.Controller.render(:"404")
    |> Plug.Conn.halt()
  end
end

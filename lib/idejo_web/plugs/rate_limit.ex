# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limits per IP address (SP-05, `Idejo.RateLimit`): `plug IdejoWeb.Plugs.RateLimit,
  :request` counts every request; controllers add `:sign_in`, `:sign_up` or
  `:reset_password` on the actions that need them. Past the limit the request gets
  `429 Too Many Requests`, with `Retry-After`, and goes no further.
  """
  @behaviour Plug

  import Plug.Conn

  alias Idejo.RateLimit

  @impl true
  def init(action) when is_atom(action), do: action

  @impl true
  def call(conn, action) do
    case RateLimit.check(action, conn.remote_ip) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        {_count, window} = RateLimit.limit(action)

        conn
        |> put_resp_header("retry-after", Integer.to_string(div(window, 1000)))
        |> put_resp_content_type("text/plain")
        |> send_resp(
          429,
          Gettext.gettext(IdejoWeb.Gettext, "Too many requests. Please try again later.")
        )
        |> halt()
    end
  end
end

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

  # AP-18: a request of the app with its device token is counted per token instead
  # (`IdejoWeb.Plugs.ApiAuth`); one whose token is not valid counts here after all.
  @impl true
  def call(%Plug.Conn{path_info: ["api", "v1" | _]} = conn, :request) do
    case get_req_header(conn, "authorization") do
      ["Bearer idj_" <> _] -> conn
      _ -> count(conn, :request)
    end
  end

  def call(conn, action), do: count(conn, action)

  @doc "Counts one `action` for the request's address; past the limit, 429."
  @spec count(Plug.Conn.t(), atom()) :: Plug.Conn.t()
  def count(conn, action) do
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

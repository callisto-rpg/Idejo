# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :idejo

  # The session is stored in a cookie that is encrypted, not only signed, and is never
  # readable by scripts or sent over plain http (SP-02).
  @session_options [
    store: :cookie,
    key: "_idejo_key",
    signing_salt: "JHZ+DXkv",
    encryption_salt: "vZ7aC6XQ",
    same_site: "Lax",
    http_only: true,
    secure: Application.compile_env!(:idejo, :secure_cookies)
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  alias IdejoWeb.ApiSocket
  # AP-15: the app's socket, apart from LiveView's, with no session or cookie. Its credential
  # is the device token as Phoenix's auth_token (a socket option: inside websocket: it is lost),
  # which another origin's page cannot have: no origin check. 404 while the API is off, 403.
  socket "/api/v1/socket", ApiSocket,
    auth_token: true,
    websocket: [check_origin: false, error_handler: {ApiSocket, :refused, []}],
    longpoll: false

  # SP-05, AD-16: what a trusted proxy says about the request (visitor's address, https, host),
  # then forced https in production. Plug.SSL comes after ClientIp, not first as Phoenix's own
  # `force_ssl` would put it, so only a trusted proxy's X-Forwarded-Proto counts.
  plug IdejoWeb.Plugs.ClientIp

  if force_ssl = Application.compile_env(:idejo, :force_ssl) do
    plug Plug.SSL, Keyword.put_new(force_ssl, :host, {__MODULE__, :host, []})
  end

  # Serve at "/" the static files from "priv/static" directory.
  #
  # When code reloading is disabled (in production), the `gzip` option serves the compressed
  # static files that `phx.digest` generates.
  plug Plug.Static,
    at: "/",
    from: :idejo,
    gzip: not code_reloading?,
    only: IdejoWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :idejo
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  # SP-05: a limit on every request, per visitor address (ClientIp, above).
  plug IdejoWeb.Plugs.RateLimit, :request
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  # What a request reads again and again, read once (Idejo.Memo).
  plug IdejoWeb.Plugs.Memo
  plug IdejoWeb.Router
end

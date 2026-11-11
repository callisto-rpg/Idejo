# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ApiSocket do
  @moduledoc """
  The official app's event stream (AP-15; steward decision, 2026-11-10): Phoenix Channels
  over a WebSocket at `/api/v1/socket`, apart from LiveView's socket.

  The device token comes in the connect params (`{"token": "idj_…"}`), never in the
  address; `token` is filtered from logs (`config :phoenix, :filter_parameters`) and this
  socket logs no connections. No cookie is read. Its id is `api_token:{token id}`, so
  revoking the token (or turning the API off) closes it (`IdejoWeb.Api.Revocations`).

  Channels: `user:me`, `topic:<id>`, `conversation:<id>` (scope `private`), `category:<id>`.

  Changes to this module get an extra careful human review (DV-06).
  """
  use Phoenix.Socket, log: false

  alias Idejo.Accounts
  alias IdejoWeb.Api.Revocations

  channel "user:me", IdejoWeb.UserChannel
  channel "topic:*", IdejoWeb.TopicChannel
  channel "conversation:*", IdejoWeb.TopicChannel
  channel "category:*", IdejoWeb.CategoryChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case Accounts.get_user_by_api_token(token) do
      {:ok, user, row} -> {:ok, socket |> assign(:user, user) |> assign(:token, row)}
      {:error, :disabled} -> {:error, :disabled}
      {:error, _reason} -> {:error, :unauthenticated}
    end
  end

  def connect(_params, _socket, _connect_info), do: {:error, :unauthenticated}

  @impl true
  def id(socket), do: Revocations.socket_id(socket.assigns.token.id)

  @doc "A refused connection: 404 while the API is off (AP-20), else 403."
  def refused(conn, :disabled, _args), do: Plug.Conn.send_resp(conn, 404, "Not Found")
  def refused(conn, _reason, _args), do: Plug.Conn.send_resp(conn, 403, "Forbidden")
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.Revocations do
  @moduledoc """
  Ends the official app's sockets (AP-09, AP-20): each `IdejoWeb.ApiSocket` has the id
  `api_token:{token id}`, so a `"disconnect"` broadcast there closes it.

    * `{:api_tokens_revoked, user_id, ids}` on `"api_tokens"` (`Idejo.Accounts.ApiTokens`):
      those tokens' sockets, a moment later, so their channels first tell the app
      `token.revoked`;
    * `{:api_disabled, ids}` on `"api_tokens"` (the API was turned off): every live token's.
  """
  use GenServer

  # Time for the channels to push `token.revoked` before the socket closes.
  @delay_ms 200

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The id of a token's sockets."
  @spec socket_id(Ecto.UUID.t()) :: String.t()
  def socket_id(token_id), do: "api_token:" <> token_id

  @impl true
  def init(nil) do
    :ok = Phoenix.PubSub.subscribe(Idejo.PubSub, "api_tokens")
    {:ok, nil}
  end

  @impl true
  def handle_info({:api_tokens_revoked, _user_id, ids}, state) do
    Process.send_after(self(), {:disconnect, ids}, @delay_ms)
    {:noreply, state}
  end

  def handle_info({:api_disabled, ids}, state) do
    disconnect(ids)
    {:noreply, state}
  end

  def handle_info({:disconnect, ids}, state) do
    disconnect(ids)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp disconnect(ids),
    do: Enum.each(ids, &IdejoWeb.Endpoint.broadcast(socket_id(&1), "disconnect", %{}))
end

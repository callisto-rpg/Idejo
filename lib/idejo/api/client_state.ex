# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Api.ClientState do
  @moduledoc """
  What a topic view keeps in its process between Enters, kept here for clients whose
  requests each run in a process of their own (AP-14; steward decision, 2026-11-10):

    * `{:typing, user_id, topic_id}`: when the author started typing their next message,
      on the server's clock (`Idejo.Messages.typing/3`), so the patience timers start at the
      first keystroke as in the web composer (GM-03), and a client can never set it back;
    * `{:edit, user_id, message_id}`: an edit in progress already kept its earlier version
      (GM-11, TP-05: one version per edit, however many Enters).

  One ETS table, owned by this process. Entries older than an hour are ignored and swept, so
  an abandoned draft or edit counts as never begun.
  """
  use GenServer

  @table __MODULE__
  @ttl_ms 3_600_000

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Keeps `value` under `key`, unless one is kept already (then returns that one)."
  @spec put_new(term(), term()) :: term()
  def put_new(key, value) do
    case get(key) do
      nil ->
        :ets.insert(@table, {key, value, now()})
        value

      kept ->
        kept
    end
  end

  @doc "The value kept under `key`, or nil (also once it is older than an hour)."
  @spec get(term()) :: term() | nil
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, at}] -> if now() - at < @ttl_ms, do: value
      [] -> nil
    end
  end

  @doc "Forgets `key`."
  @spec delete(term()) :: :ok
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end

  defp now, do: System.monotonic_time(:millisecond)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    Process.send_after(self(), :sweep, @ttl_ms)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    limit = now() - @ttl_ms
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", limit}], [true]}])
    Process.send_after(self(), :sweep, @ttl_ms)
    {:noreply, state}
  end
end

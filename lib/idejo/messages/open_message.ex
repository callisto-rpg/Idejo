# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.OpenMessage do
  @moduledoc """
  One process per open message, holding its window timer (CLAUDE.md growing-message
  invariant 3). The database is the truth; this process is only a timer.

  When `closes_at` comes it broadcasts `{:window_ended, message_id}` on the topic, so the
  author's composer knows Ctrl+Enter now starts a new message (GM-04, GM-05), and stops. The
  message itself stays open: the window never closes it (GM-03).
  """
  use GenServer, restart: :transient

  alias Idejo.Messages

  @doc "Starts the timer of an open message, under `Idejo.Messages.OpenMessageSupervisor`."
  @spec start(Idejo.Messages.Message.t()) :: :ok
  def start(message) do
    case DynamicSupervisor.start_child(
           Idejo.Messages.OpenMessageSupervisor,
           {__MODULE__, Map.take(message, [:id, :topic_id, :closes_at])}
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @doc "Stops the timer of a message, if it runs."
  @spec stop(Ecto.UUID.t()) :: :ok
  def stop(message_id) do
    case Registry.lookup(Idejo.Messages.Registry, message_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
      [] -> :ok
    end

    :ok
  end

  @doc "Returns true when the message's timer runs."
  @spec running?(Ecto.UUID.t()) :: boolean()
  def running?(message_id) do
    # The Registry forgets a stopped process a moment later; ask the process itself.
    case Registry.lookup(Idejo.Messages.Registry, message_id) do
      [{pid, _}] -> Process.alive?(pid)
      [] -> false
    end
  end

  def start_link(%{id: id} = message),
    do: GenServer.start_link(__MODULE__, message, name: via(id))

  defp via(id), do: {:via, Registry, {Idejo.Messages.Registry, id}}

  @impl true
  def init(%{closes_at: closes_at} = message) do
    left = max(DateTime.diff(closes_at, DateTime.utc_now(), :millisecond), 0)
    Process.send_after(self(), :window_ended, left)
    {:ok, message}
  end

  @impl true
  def handle_info(:window_ended, message) do
    Messages.broadcast(message.topic_id, {:window_ended, message.id})
    {:stop, :normal, message}
  end
end

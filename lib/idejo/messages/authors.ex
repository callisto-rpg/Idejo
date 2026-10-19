# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Authors do
  @moduledoc """
  Who is connected to which topic, so an open message closes when its author's session
  disconnects (GM-12).

  Steward decision: not at once, which would close a message on every reload or brief network
  drop, but when the author has had **no live view of the topic for 30 seconds** (the
  `:gm_disconnect_grace_ms` setting of the app, default 30,000). Coming back within that time
  cancels it. After a server restart nobody is connected yet, so `Idejo.Messages.Recovery`
  starts the same grace for every open message.

  A live topic view calls `present/2`; this process monitors it. When the last view of a
  topic by a user goes away, the grace starts; at its end `Idejo.Messages.close_for_author/2`
  closes their open message there, if one is still open.
  """
  use GenServer

  alias Idejo.Messages

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Records that the calling process is a live view of `topic_id` by `user_id`, and cancels a
  grace running for them there.
  """
  @spec present(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: :ok
  def present(topic_id, user_id, opts \\ []) do
    grace = Keyword.get(opts, :grace_ms, grace_ms())
    # The callers chain lets the close run with the caller's database access in tests.
    callers = [self() | Process.get(:"$callers", [])]
    GenServer.call(__MODULE__, {:present, {topic_id, user_id}, self(), grace, callers})
  end

  @doc "Starts the grace for an author with no live view of the topic, e.g. after a restart."
  @spec absent(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: :ok
  def absent(topic_id, user_id, opts \\ []) do
    grace = Keyword.get(opts, :grace_ms, grace_ms())
    callers = [self() | Process.get(:"$callers", [])]
    GenServer.call(__MODULE__, {:absent, {topic_id, user_id}, grace, callers})
  end

  @doc "Returns true when the user has a live view of the topic."
  @spec present?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def present?(topic_id, user_id),
    do: GenServer.call(__MODULE__, {:present?, {topic_id, user_id}})

  defp grace_ms, do: Application.get_env(:idejo, :gm_disconnect_grace_ms, 30_000)

  # State: %{key => %{views: %{ref => pid}, timer: ref | nil, grace: ms, callers: list}}

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:present, key, pid, grace, callers}, _from, state) do
    ref = Process.monitor(pid)
    entry = Map.get(state, key, %{views: %{}, timer: nil})
    cancel(entry.timer)
    entry = %{entry | views: Map.put(entry.views, ref, pid), timer: nil}
    {:reply, :ok, Map.put(state, key, Map.merge(entry, %{grace: grace, callers: callers}))}
  end

  def handle_call({:absent, key, grace, callers}, _from, state) do
    entry = Map.get(state, key, %{views: %{}, timer: nil})

    if map_size(entry.views) == 0 do
      cancel(entry.timer)
      timer = Process.send_after(self(), {:grace_over, key}, grace)
      {:reply, :ok, Map.put(state, key, Map.merge(entry, %{timer: timer, callers: callers}))}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:present?, key}, _from, state) do
    {:reply, map_size(get_in(state, [key, :views]) || %{}) > 0, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state, fn {_key, entry} -> Map.has_key?(entry.views, ref) end) do
      nil ->
        {:noreply, state}

      {key, entry} ->
        views = Map.delete(entry.views, ref)

        timer =
          if map_size(views) == 0,
            do: Process.send_after(self(), {:grace_over, key}, entry.grace),
            else: entry.timer

        {:noreply, Map.put(state, key, %{entry | views: views, timer: timer})}
    end
  end

  def handle_info({:grace_over, {topic_id, user_id} = key}, state) do
    case Map.get(state, key) do
      %{views: views, callers: callers} when map_size(views) == 0 ->
        close(topic_id, user_id, callers)
        {:noreply, Map.delete(state, key)}

      _ ->
        {:noreply, state}
    end
  end

  # Closed in its own process, so a slow database never holds up this one.
  defp close(topic_id, user_id, callers) do
    Task.start(fn ->
      Process.put(:"$callers", callers)
      Messages.close_for_author(topic_id, user_id)
    end)
  end

  defp cancel(nil), do: :ok
  defp cancel(timer), do: Process.cancel_timer(timer) && :ok
end

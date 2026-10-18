# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.DemoTopic do
  @moduledoc """
  In-memory prototype of one live topic, used to try the composer before M3.

  It follows the growing-message rules (GM-02 to GM-05, GM-09, GM-12) but keeps
  messages in memory only, so it does not satisfy NF-02 and must be replaced by
  the database-backed engine in M3.
  """

  use GenServer

  @pubsub Idejo.PubSub
  @topic "demo_topic"

  @type author :: %{id: String.t(), name: String.t(), role: String.t()}

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  def list(server \\ __MODULE__), do: GenServer.call(server, :list)

  @doc """
  Commits `body` as the full text of the author's open message, opening one if
  needed (GM-01, GM-02). With `break: true` (Ctrl+Enter) the message closes when
  its window has ended (GM-05). Returns `{:ok, message}`.
  """
  def commit(server, author, body, opts \\ []) do
    GenServer.call(server, {:commit, author, body, Keyword.get(opts, :break, false), self()})
  end

  @impl true
  def init(opts) do
    window =
      Keyword.get(opts, :window_seconds, Application.get_env(:idejo, :gm_window_seconds, 45))

    {:ok,
     %{messages: [], next_id: 1, window: window, broadcast: Keyword.get(opts, :broadcast, true)}}
  end

  @impl true
  def handle_call(:list, _from, state), do: {:reply, state.messages, state}

  def handle_call({:commit, author, body, break?, pid}, _from, state) do
    now = System.system_time(:millisecond)

    {message, state} =
      case open_message(state, author.id) do
        nil -> open(state, author, body, now, pid)
        message -> {%{message | body: body}, state}
      end

    message =
      if break? and now >= message.closes_at, do: %{message | state: :closed}, else: message

    state = put_message(state, message) |> broadcast()
    {:reply, {:ok, message}, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # GM-12: the author's session went away, so their open message closes.
    messages =
      Enum.map(state.messages, fn
        %{state: :open, pid: ^pid} = m -> %{m | state: :closed}
        m -> m
      end)

    {:noreply, broadcast(%{state | messages: messages})}
  end

  defp open(state, author, body, now, pid) do
    Process.monitor(pid)

    message = %{
      id: state.next_id,
      author: author,
      body: body,
      state: :open,
      pid: pid,
      opened_at: now,
      closes_at: now + state.window * 1000
    }

    {message, %{state | messages: state.messages ++ [message], next_id: state.next_id + 1}}
  end

  defp open_message(state, author_id) do
    Enum.find(state.messages, &(&1.state == :open and &1.author.id == author_id))
  end

  defp put_message(state, message) do
    %{state | messages: Enum.map(state.messages, &if(&1.id == message.id, do: message, else: &1))}
  end

  defp broadcast(%{broadcast: false} = state), do: state

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:messages, state.messages})
    state
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Memo do
  @moduledoc """
  What one request (or one LiveView mount) reads again and again, read once: the viewer's
  roles, the settings, the answer to a permission check (NF-04). A topic page asked the
  database for the same roles some twenty times, one per permission check, and for the
  settings one key at a time.

  Off unless `run/1` (a LiveView's mount) or `start/0` and `stop/0` (each request, from
  `IdejoWeb.Plugs.Memo`) turn it on for the process; it lives in the process dictionary, so
  nothing is shared between requests, processes or test sandboxes, and it starts empty each
  time. A LiveView's later events never use it: a role or a setting changed meanwhile counts
  at once there. Writes to roles, permissions or settings `forget/0` it, so a request that
  changes them reads them fresh afterwards.
  """

  @key {__MODULE__, :memo}

  @doc "Turns the memo on, empty, for this process."
  @spec start() :: :ok
  def start do
    Process.put(@key, %{})
    :ok
  end

  @doc "Whether the memo is on for this process."
  @spec on?() :: boolean()
  def on?, do: Process.get(@key) != nil

  @doc "Turns the memo off for this process, dropping what it held."
  @spec stop() :: :ok
  def stop do
    Process.delete(@key)
    :ok
  end

  @doc """
  Runs `fun` with the memo on, then off again (whatever `fun` does). Already on (a LiveView
  rendered in a request), it goes on with what the request read.
  """
  @spec run((-> result)) :: result when result: term()
  def run(fun) do
    if on?() do
      fun.()
    else
      start()

      try do
        fun.()
      after
        stop()
      end
    end
  end

  @doc """
  The value for `key`: the one worked out earlier while the memo is on, else `fun.()` (kept
  for next time while it is on).
  """
  @spec fetch(term(), (-> value)) :: value when value: term()
  def fetch(key, fun) do
    case Process.get(@key) do
      nil ->
        fun.()

      %{^key => value} ->
        value

      memo ->
        value = fun.()
        Process.put(@key, Map.put(memo, key, value))
        value
    end
  end

  @doc "Forgets everything held, after a write that changes what it would answer."
  @spec forget() :: :ok
  def forget do
    if Process.get(@key), do: Process.put(@key, %{})
    :ok
  end
end

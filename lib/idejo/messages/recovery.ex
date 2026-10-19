# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Recovery do
  @moduledoc """
  Restarts the window timers of open messages at boot (CLAUDE.md growing-message invariant
  4, NF-02), with their original `closes_at`: a restart neither loses sent text, which is in
  the database, nor gives a message a new window. Messages whose window ended while the
  server was down stay open, as they would have (GM-04). Nobody is connected yet, so each
  author gets the disconnect grace (GM-12, `Idejo.Messages.Authors`): an author who does not
  come back within it has their message closed.
  """
  use Task, restart: :temporary

  import Ecto.Query

  alias Idejo.Messages.{Authors, Message, OpenMessage}
  alias Idejo.Repo

  def start_link(_opts), do: Task.start_link(&run/0)

  @doc """
  Starts a timer for every open message whose window has not ended, and the disconnect grace
  for every open message's author. Returns how many timers it started.
  """
  @spec run() :: non_neg_integer()
  def run do
    now = DateTime.utc_now()

    open = Repo.all(from m in Message, where: m.state == "open")

    # Nobody is connected after a restart: each author gets the disconnect grace (GM-12).
    Enum.each(open, &Authors.absent(&1.topic_id, &1.author_id))

    open
    |> Enum.filter(&(DateTime.compare(&1.closes_at, now) == :gt))
    |> Enum.map(&OpenMessage.start/1)
    |> length()
  end
end

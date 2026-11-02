# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.Memo do
  @moduledoc """
  Turns `Idejo.Memo` on for one request: the viewer's roles, the settings and permission
  checks are read once while it is handled (NF-04), and dropped when the response goes. It
  starts empty at every request, so a process that serves several requests (keep-alive)
  never carries one's reads into the next, even after a crash.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    :ok = Idejo.Memo.start()

    register_before_send(conn, fn conn ->
      :ok = Idejo.Memo.stop()
      conn
    end)
  end
end

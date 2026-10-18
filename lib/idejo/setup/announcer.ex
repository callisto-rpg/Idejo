# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Setup.Announcer do
  @moduledoc """
  Writes the setup link to the log once the database is up (AD-01). Turned off in tests.
  """
  use Task, restart: :temporary

  def start_link(_arg), do: Task.start_link(&Idejo.Setup.announce/0)
end

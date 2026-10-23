# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.HelpController do
  @moduledoc """
  The Help page at `/help`, linked from the sidebar under "Rules & Roles" (steward decision,
  2026-10-23): the keys that send, the signs that link or suggest (`@`, `+`, `#`, `/`, `$`,
  `!`) and every `!` command (`IdejoWeb.ComposerCommands`). Public, no JavaScript needed.
  """
  use IdejoWeb, :controller

  def show(conn, _params) do
    render(conn, :show,
      page_title: gettext("Help"),
      window: Idejo.Settings.get(:gm_window_seconds),
      commands: IdejoWeb.ComposerCommands.all()
    )
  end
end

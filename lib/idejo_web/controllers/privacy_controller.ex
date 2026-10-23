# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PrivacyController do
  @moduledoc """
  The privacy notice at `/privacy` (AD-02, legal pages), linked from every page's footer: the
  `privacy_notice` setting, Markdown written in **Admin → Settings**. Public, no JavaScript
  needed.
  """
  use IdejoWeb, :controller

  def show(conn, _params) do
    render(conn, :show,
      page_title: gettext("Privacy"),
      notice: Idejo.Settings.get(:privacy_notice)
    )
  end
end

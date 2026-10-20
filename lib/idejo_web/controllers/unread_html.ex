# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UnreadHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.UnreadController`.
  """
  use IdejoWeb, :html

  import IdejoWeb.CategoryHTML, only: [unread_marker: 1]

  embed_templates "unread_html/*"
end

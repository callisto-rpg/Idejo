# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.UserController`.
  """
  use IdejoWeb, :html

  import IdejoWeb.UserComponents, only: [user_card: 1]

  embed_templates "user_html/*"
end

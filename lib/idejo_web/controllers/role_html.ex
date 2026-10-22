# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.RoleHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.RoleController`.
  """
  use IdejoWeb, :html

  alias IdejoWeb.Admin

  embed_templates "role_html/*"
end

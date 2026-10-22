# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CategoryHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.CategoryController`.
  """
  use IdejoWeb, :html

  embed_templates "category_html/*"
end

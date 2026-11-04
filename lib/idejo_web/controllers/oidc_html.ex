# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.OIDCHTML do
  @moduledoc "AC-09: the page asking someone new whether to join through the provider."
  use IdejoWeb, :html

  embed_templates "oidc_html/*"
end

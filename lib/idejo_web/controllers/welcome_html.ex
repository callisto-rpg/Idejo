# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.WelcomeHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.WelcomeController`.
  """
  use IdejoWeb, :html

  embed_templates "welcome_html/*"
end

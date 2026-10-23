# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.HelpHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.HelpController`.
  """
  use IdejoWeb, :html

  embed_templates "help_html/*"
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ConversationHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.ConversationController`.
  """
  use IdejoWeb, :html

  embed_templates "conversation_html/*"
end

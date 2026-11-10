# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InboxHTML do
  @moduledoc "The inbox's pages (steward request, 2026-11-10)."
  use IdejoWeb, :html

  alias IdejoWeb.TopicComponents

  embed_templates "inbox_html/*"
end

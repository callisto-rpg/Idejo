# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.TopicController`.
  """
  use IdejoWeb, :html

  embed_templates "topic_html/*"
end

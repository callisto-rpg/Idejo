# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TagHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.TagController`.
  """
  use IdejoWeb, :html

  embed_templates "tag_html/*"

  @doc "The address of another page of the same filter."
  def page_path(selected, op, page),
    do: ~p"/tags?#{%{"tags" => Enum.map(selected, & &1.slug), "op" => op, "page" => page}}"
end

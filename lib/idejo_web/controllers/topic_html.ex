# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.TopicController`.
  """
  use IdejoWeb, :html

  embed_templates "topic_html/*"

  @doc """
  A message's body: the HTML stored with it, sanitised when it was saved (FD-03,
  `Idejo.Markdown`), so it is shown as is.
  """
  attr :message, :map, required: true

  # body_html is sanitised by Idejo.Markdown before it is stored; this is the one place it
  # is shown raw.
  # sobelow_skip ["XSS.Raw"]
  def body(assigns) do
    ~H"""
    <div class="message-body">{Phoenix.HTML.raw(@message.body_html)}</div>
    """
  end
end

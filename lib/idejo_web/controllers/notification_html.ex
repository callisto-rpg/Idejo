# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.NotificationHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.NotificationController`.
  """
  use IdejoWeb, :html

  embed_templates "notification_html/*"

  @doc "What happened, in words: who did what, in which topic."
  def headline(%{kind: kind, message: %{author: author, topic: topic}}) do
    name = author.display_name

    case kind do
      "mention" -> gettext("%{name} mentioned you in “%{topic}”", name: name, topic: topic.title)
      "reply" -> gettext("%{name} replied to you in “%{topic}”", name: name, topic: topic.title)
      "follow" -> gettext("%{name} posted in “%{topic}”", name: name, topic: topic.title)
    end
  end
end

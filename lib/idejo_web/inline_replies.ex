# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InlineReplies do
  @moduledoc """
  Inline replies (TP-08; steward decision, 2026-11-06): Reply on a message above the one
  being written puts its quote into that message, where the author is writing, as Markdown.
  A message may hold several.

  The quote is a block quote of two links to the message's permalink, "Replying to NAME:"
  then its excerpt:

      > [Replying to Alice:](/m/ID)
      > [the excerpt…](/m/ID)

  Inside links, the name and the excerpt are never read as inline links (`@user`, `+role`…:
  `Idejo.Markdown.references/1`), so quoting notifies nobody they name. The quoted message's
  author is notified as for a reply (`Idejo.Markdown.quoted_messages/1`).
  """

  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Forum
  alias Idejo.Messages.Message

  # Read as Markdown inside a link's text: escaped so the excerpt shows as written.
  @special ~r/[\\`*_\[\]<>~=|^!&]/

  @doc "The Markdown of a quote of `message`, which must have its author loaded."
  @spec markdown(Message.t()) :: String.t()
  def markdown(%Message{id: id} = message) do
    path = "/m/" <> id

    head =
      "> [" <>
        escape(gettext("Replying to %{name}:", name: Idejo.Messages.author_name(message))) <>
        "](#{path})"

    case Forum.excerpt(message) do
      "" -> head
      excerpt -> head <> "\n> [" <> escape(excerpt) <> "](#{path})"
    end
  end

  defp escape(text), do: Regex.replace(@special, text, "\\\\\\0")
end

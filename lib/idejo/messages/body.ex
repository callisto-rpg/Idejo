# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Body do
  @moduledoc """
  A message body's HTML (FD-03) with its @mentions (TP-10): every `@username` naming an
  active user links to that user's URI path, `/u/{id}`. Unknown names stay plain text.
  Messages, previews and earlier versions all render through here.
  """
  import Ecto.Query

  alias Idejo.Accounts.User
  alias Idejo.Repo

  @doc "Renders a message's Markdown to sanitised HTML, with its mentions linked."
  @spec to_html(String.t()) :: String.t()
  def to_html(markdown) when is_binary(markdown) do
    users = Map.new(mentioned_users(markdown), &{String.downcase(&1.username), &1.id})
    Idejo.Markdown.to_html(markdown, mentions: users)
  end

  @doc """
  The active users mentioned in the Markdown (TP-10), each once, outside code and links.
  For notifications (NO-01).
  """
  @spec mentioned_users(String.t()) :: [User.t()]
  def mentioned_users(markdown) when is_binary(markdown) do
    case Idejo.Markdown.mentions(markdown) do
      [] ->
        []

      names ->
        Repo.all(
          from u in User,
            where: fragment("lower(?)", u.username) in ^names and u.status == "active"
        )
    end
  end
end

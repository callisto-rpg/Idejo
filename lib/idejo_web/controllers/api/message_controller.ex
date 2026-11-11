# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.MessageController do
  @moduledoc """
  One message (AP-12, AP-14): reading it, the author's edit (Enter keeps editing, `finish`
  is Ctrl+Enter: one version per edit, GM-11) and delete, earlier versions for moderators
  (MO-06), spoilers, a new topic from it (TP-09), forwarding targets, reactions (TP-17) and
  reports (MO-01).
  """
  use IdejoWeb.Api.Controller

  alias Idejo.Forum.Forwards
  alias Idejo.{Messages, Moderation, Reactions}
  alias IdejoWeb.Api.CategoryController

  def show(conn, %{"id" => id}) do
    with {:ok, message} <- readable_message(conn, id),
         do: json(conn, Api.message(user(conn), message))
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, message} <- readable_message(conn, id),
         body when is_binary(body) <- string(params, "body_md") || {:error, :bad_request},
         {:ok, edited} <-
           Messages.edit_from_client(user(conn), message, body, boolean(params, "finish")) do
      json(conn, Api.message(user(conn), edited))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, message} <- readable_message(conn, id),
         {:ok, deleted} <- Messages.delete_own(user(conn), message) do
      json(conn, Api.message(user(conn), deleted))
    end
  end

  # MO-06 (steward request, 2026-11-09): only those who moderate the category see versions.
  def versions(conn, %{"id" => id}) do
    with {:ok, message} <- readable_message(conn, id),
         true <- Api.moderator?(user(conn), message.topic) || {:error, :forbidden} do
      send_list(
        conn,
        for version <- Messages.list_versions(message) do
          %{
            "id" => version.id,
            "body_md" => version.body_md,
            "created_at" => Api.time(version.created_at)
          }
        end
      )
    end
  end

  def spoiler(conn, %{"id" => id} = params),
    do: set_spoiler(conn, id, true, string(params, "overlay"))

  def unspoiler(conn, %{"id" => id}), do: set_spoiler(conn, id, false, nil)

  defp set_spoiler(conn, id, spoiler?, overlay) do
    with {:ok, message} <- readable_message(conn, id),
         {:ok, message} <- Messages.set_spoiler(user(conn), message, spoiler?, overlay) do
      json(conn, Api.message(user(conn), message))
    end
  end

  @doc "A new topic continuing from the message (TP-09): `title`, `category_id`, `tag_ids`, `body_md`."
  def new_topic(conn, %{"id" => id} = params) do
    with {:ok, message} <- readable_message(conn, id),
         {:ok, category} <- CategoryController.category(conn, params["category_id"]) do
      params = Map.put_new(params, "tag_ids", params["tags"])
      CategoryController.create(conn, category, params, forked_from: message)
    end
  end

  def forward_targets(conn, params) do
    targets = Forwards.targets(user(conn), string(params, "q") || "", string(params, "except"))

    send_list(
      conn,
      for target <- targets do
        %{
          "id" => target.id,
          "title" => target.title,
          "url" => Api.absolute(target.path),
          "private" => target.place == :private,
          "place" => if(target.place == :private, do: nil, else: target.place)
        }
      end
    )
  end

  def react(conn, %{"id" => id, "emoji" => emoji}), do: reaction(conn, id, emoji, true)
  def unreact(conn, %{"id" => id, "emoji" => emoji}), do: reaction(conn, id, emoji, false)

  defp reaction(conn, id, emoji, wanted?) do
    with {:ok, message} <- readable_message(conn, id),
         {:ok, summary} <- Reactions.set(user(conn), message, emoji, wanted?) do
      send_list(conn, Api.reactions(summary, user(conn)))
    end
  end

  def reactions(conn, %{"id" => id}) do
    with {:ok, message} <- readable_message(conn, id) do
      reactors =
        for %{user: who, emoji: emoji} <- Reactions.reactors(user(conn), message.id),
            do: %{"user" => Api.person(who), "emoji" => Enum.map(emoji, &(":" <> &1 <> ":"))}

      send_list(conn, reactors)
    end
  end

  def report(conn, %{"id" => id} = params) do
    with {:ok, message} <- readable_message(conn, id),
         {:ok, _report} <-
           Moderation.report_message(user(conn), message, %{"reason" => params["reason"]}) do
      no_content(conn)
    end
  end
end

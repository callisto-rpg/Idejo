# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicModerationController do
  @moduledoc """
  The topic page's moderator form: lock, unlock, pin or unpin (TP-14), move to another
  category (TP-15), archive, or delete for good (steward decision, 2026-10-23; only with its
  confirmation box ticked), with an optional reason for the moderation log (MO-03). A plain
  form post, so it works without JavaScript.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum

  @actions %{"lock" => :lock, "unlock" => :unlock, "pin" => :pin, "unpin" => :unpin}

  def create(conn, %{"id" => id, "action" => "move"} = params) do
    user = conn.assigns.current_scope.user

    with %{} = topic <- Forum.get_viewable_topic(user, id),
         %{} = target <-
           Enum.find(Forum.list_move_targets(user, topic), &(&1.id == params["category_id"])) do
      case Forum.move_topic(user, topic, target, params["reason"]) do
        {:ok, _} ->
          conn
          |> put_flash(:info, gettext("Topic moved to %{category}.", category: target.name))
          |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")

        {:error, _} ->
          conn
          |> put_flash(:error, gettext("You cannot move this topic there."))
          |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
      end
    else
      _ -> raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic
    end
  end

  def create(conn, %{"id" => id, "action" => "archive"} = params) do
    user = conn.assigns.current_scope.user

    topic =
      Forum.get_viewable_topic(user, id) ||
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic

    case Forum.archive_topic(user, topic, params["reason"]) do
      {:ok, archived} ->
        conn
        |> put_flash(:info, gettext("Topic archived: it is read only now."))
        |> redirect(to: back_to(user, archived))

      {:error, :archived} ->
        conn
        |> put_flash(:error, gettext("This topic is archived already."))
        |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("You cannot moderate this topic."))
        |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
    end
  end

  def create(conn, %{"id" => id, "action" => "delete"} = params) do
    user = conn.assigns.current_scope.user

    topic =
      Forum.get_viewable_topic(user, id) ||
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic

    cond do
      params["confirm"] != "yes" ->
        conn
        |> put_flash(:error, gettext("Tick the box to confirm, then delete the topic."))
        |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")

      match?({:ok, _}, Forum.delete_topic(user, topic, params["reason"])) ->
        conn
        |> put_flash(:info, gettext("Topic deleted for good."))
        |> redirect(to: ~p"/c/#{topic.category.slug}")

      true ->
        conn
        |> put_flash(:error, gettext("You cannot moderate this topic."))
        |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
    end
  end

  def create(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    with %{} = topic <- Forum.get_viewable_topic(user, id),
         {:ok, action} <- Map.fetch(@actions, params["action"]) do
      conn
      |> put_flash_for(Forum.moderate_topic(user, topic, action, params["reason"]), action)
      |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
    else
      _ -> raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic
    end
  end

  # The archived topic, when the moderator may still view it (the Archive is hidden from every
  # role until an administrator shows it); else the category it left.
  defp back_to(user, topic) do
    if Forum.get_viewable_topic(user, topic.id),
      do: ~p"/t/#{topic.id}/#{topic.slug}",
      else: ~p"/"
  end

  defp put_flash_for(conn, {:ok, _topic}, action), do: put_flash(conn, :info, done(action))

  defp put_flash_for(conn, {:error, :archived}, _action),
    do: put_flash(conn, :error, gettext("Archived topics are neither locked nor unlocked."))

  defp put_flash_for(conn, {:error, _}, _action),
    do: put_flash(conn, :error, gettext("You cannot moderate this topic."))

  defp done(:lock), do: gettext("Topic locked.")
  defp done(:unlock), do: gettext("Topic unlocked.")
  defp done(:pin), do: gettext("Topic pinned.")
  defp done(:unpin), do: gettext("Topic unpinned.")
end

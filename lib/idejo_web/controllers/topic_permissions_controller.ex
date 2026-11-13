# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicPermissionsController do
  @moduledoc """
  A topic's own permissions (steward request, 2026-11-13; `Idejo.Access.set_topic_permissions/3`):
  for those with the `:moderate` right there, each role's view, post, moderate and edit-tags
  rights on this topic, allowed, denied or as its category has them. A plain form, so it works
  without JavaScript; each change is logged (`topic.permission`, MO-03). A topic they may not
  view or do not moderate is not found, as a missing one.
  """
  use IdejoWeb, :controller

  alias Idejo.Access
  alias Idejo.Forum

  def show(conn, %{"id" => id}) do
    with {:ok, topic} <- moderated_topic(conn, id) do
      render(conn, :show,
        page_title: gettext("Permissions of “%{topic}”", topic: topic.title),
        topic: topic,
        roles: roles(),
        rights: Access.topic_rights(),
        own: Access.topic_permissions(topic),
        inherited: Access.category_rights(topic)
      )
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, topic} <- moderated_topic(conn, id) do
      user = conn.assigns.current_scope.user

      case Access.set_topic_permissions(user, topic, params["permissions"] || %{}) do
        :ok ->
          conn
          |> put_flash(:info, gettext("Topic permissions saved."))
          |> redirect(to: back(user, topic))

        {:error, _reason} ->
          conn
          |> put_flash(:error, gettext("Some permissions could not be saved."))
          |> redirect(to: ~p"/topic-permissions/#{topic.id}")
      end
    end
  end

  # Owner and administrator always have every right: no setting to show.
  defp roles,
    do: Enum.reject(Access.list_roles(), &(&1.built_in and &1.name in ~w(owner administrator)))

  defp moderated_topic(conn, id) do
    user = conn.assigns.current_scope.user

    case Forum.get_viewable_topic(user, id) do
      %{private: false} = topic ->
        if Access.can?(user, :moderate, topic), do: {:ok, topic}, else: not_found()

      _ ->
        not_found()
    end
  end

  defp not_found, do: raise(Ecto.NoResultsError, queryable: Idejo.Forum.Topic)

  # Back to the topic, or home when the moderator no longer sees it.
  defp back(user, topic) do
    if Forum.get_viewable_topic(user, topic.id), do: ~p"/t/#{topic.id}/#{topic.slug}", else: ~p"/"
  end
end

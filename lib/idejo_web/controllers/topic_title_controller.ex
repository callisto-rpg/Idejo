# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicTitleController do
  @moduledoc """
  The topic page's title form (steward decision, 2026-10-23), opened by the pencil next to
  the title: for the topic's starter and for moderators of its category
  (`Idejo.Forum.can_rename_topic?/2`). A plain form post, so it works without JavaScript;
  the page comes back at the new address.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    case Forum.get_viewable_topic(user, id) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Topic

      topic ->
        title = if is_binary(params["title"]), do: params["title"], else: ""

        case Forum.rename_topic(user, topic, title) do
          {:ok, renamed} ->
            conn
            |> put_flash(:info, gettext("Title saved."))
            |> redirect(to: ~p"/t/#{renamed.id}/#{renamed.slug}")

          {:error, %Ecto.Changeset{}} ->
            conn
            |> put_flash(
              :error,
              gettext("The title cannot be empty or longer than 150 characters.")
            )
            |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")

          {:error, _} ->
            conn
            |> put_flash(:error, gettext("You cannot change the title of this topic."))
            |> redirect(to: ~p"/t/#{topic.id}/#{topic.slug}")
        end
    end
  end
end

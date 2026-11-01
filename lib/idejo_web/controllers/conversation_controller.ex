# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ConversationController do
  @moduledoc """
  Private conversations (steward decision, 2026-10-27; `Idejo.Conversations`), for signed-in
  users: `/p`, the list of the user's conversations as cards; `/p/{id}`, one conversation,
  its messages and composer from `IdejoWeb.TopicLive` as on a topic page; and
  `POST /u/{id}/message`, the user card's "Private Message", which opens the conversation
  with that user (started on first use). All work without JavaScript.
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts
  alias Idejo.Conversations
  alias Idejo.Reading

  def index(conn, _params) do
    render(conn, :index,
      page_title: gettext("Private Conversations"),
      conversations: Conversations.list(conn.assigns.current_scope.user)
    )
  end

  def show(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    case Conversations.get(user, id) do
      nil ->
        IdejoWeb.Unavailable.redirect_away(conn, :topic)

      topic ->
        first_unread = Reading.first_unread(user, topic)
        Reading.mark_read(user, topic)
        others = Conversations.others(topic, user)

        render(conn, :show,
          topic: topic,
          others: others,
          page_title: title(others),
          reply_to_id: params["reply_to"],
          first_unread: first_unread,
          window: IdejoWeb.TopicController.window(params)
        )
    end
  end

  def create(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = recipient <- Accounts.get_user(id),
         {:ok, topic} <- Conversations.start(user, recipient) do
      redirect(conn, to: ~p"/p/#{topic.id}")
    else
      {:error, :rate_limited} ->
        conn
        |> put_flash(
          :error,
          gettext("You are starting conversations too quickly. Try again later.")
        )
        |> redirect(to: ~p"/u/#{id}")

      _ ->
        conn
        |> put_flash(:error, gettext("You cannot send this user a private message."))
        |> redirect(to: ~p"/p")
    end
  end

  @doc false
  def title([]), do: gettext("Private conversation")
  def title(others), do: Enum.map_join(others, ", ", & &1.display_name)
end

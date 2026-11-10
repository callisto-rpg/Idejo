# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InboxController do
  @moduledoc """
  The inbox's pages (steward request, 2026-11-10; `Idejo.Inbox`), only in inbox mode (404
  otherwise), for signed-in members, plain pages that work without JavaScript:

    * `forums/2` (`/`): the communities the member joined, as cards with their logos;
    * `topics/2` (`/topics`): the topics they follow there, Idejo's topic rows (`?view=`
      compact or expanded, as the home page's, `IdejoWeb.TopicView`; `?show=` all or
      unread only, remembered in the session);
    * `chats/2` (`/chat`): their private conversations, after copying those still in the
      forums (`Inbox.import/1`); `ConversationController` shows each;
    * `new_chat/2` (`/chat/new?with=<subject>`): a forum's "Private Message": the
      conversation with that person, started on first use (`Inbox.member/1`);
    * `unread/2` (`GET /community/inbox-unread?subject=`, JSON, no session): for the group's service,
      with this server's own client credentials.
  """
  use IdejoWeb, :controller

  alias Idejo.{Community, Conversations, Inbox}

  plug :inbox_only

  defp inbox_only(conn, _opts) do
    if Inbox.on?(), do: conn, else: conn |> send_resp(404, "Not found") |> halt()
  end

  def forums(conn, _params) do
    case conn.assigns.current_scope do
      %{user: %{} = user} ->
        conn
        |> put_view(IdejoWeb.InboxHTML)
        |> render(:forums,
          page_title: gettext("Forums"),
          communities: Community.communities(user)
        )

      _ ->
        redirect(conn, to: ~p"/users/sign-in")
    end
  end

  def topics(conn, params) do
    {conn, view} = IdejoWeb.TopicView.choose(conn, params)
    {conn, show} = choose_show(conn, params)
    entries = Inbox.topics(conn.assigns.current_scope.user)

    render(conn, :topics,
      page_title: gettext("Topics"),
      entries: if(show == :unread, do: Enum.filter(entries, & &1.unread), else: entries),
      view: view,
      show: show
    )
  end

  # "Show" (steward request, 2026-11-10): all followed topics, or only those with unread
  # messages; `?show=`, remembered in the session like the View.
  @shows %{"all" => :all, "unread" => :unread}

  defp choose_show(conn, %{"show" => show}) when is_map_key(@shows, show),
    do: {put_session(conn, :inbox_show, show), @shows[show]}

  defp choose_show(conn, _params),
    do: {conn, Map.get(@shows, get_session(conn, :inbox_show), :all)}

  def chats(conn, _params) do
    user = conn.assigns.current_scope.user
    %{remaining: remaining} = Inbox.import(user)

    conn
    |> put_view(IdejoWeb.ConversationHTML)
    |> render(:index,
      page_title: gettext("Chats"),
      conversations: Conversations.list(user),
      remaining: remaining
    )
  end

  def new_chat(conn, params) do
    user = conn.assigns.current_scope.user

    with {:ok, recipient} <- Inbox.member(params["with"]),
         {:ok, topic} <- Conversations.start(user, recipient) do
      redirect(conn, to: ~p"/p/#{topic.id}")
    else
      {:error, :rate_limited} ->
        conn
        |> put_flash(
          :error,
          gettext("You are starting conversations too quickly. Try again later.")
        )
        |> redirect(to: ~p"/chat")

      _ ->
        conn
        |> put_flash(:error, gettext("You cannot send this user a private message."))
        |> redirect(to: ~p"/chat")
    end
  end

  def unread(conn, %{"subject" => subject}) when is_binary(subject) and subject != "" do
    if Inbox.service?(Plug.BasicAuth.parse_basic_auth(conn)),
      do:
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{unread: Inbox.unread(subject)}),
      else: conn |> put_status(401) |> json(%{error: "unauthorized"})
  end

  def unread(conn, _params), do: conn |> put_status(401) |> json(%{error: "unauthorized"})
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InboxController do
  @moduledoc """
  The inbox's pages (steward request, 2026-11-10; `Idejo.Inbox`), only in inbox mode (404
  otherwise), for signed-in members, plain pages that work without JavaScript:

    * `forums/2` (`/`): the communities the member joined, as cards with their logos, each
      with "N new messages": the unread messages in the topics they follow there (steward
      request, 2026-11-13; `Inbox.topics/1`, as the Topics tab counts them);
    * `topics/2` (`/topics`): the topics they follow there, idejo's topic rows with the
      forum's logo and the activity lines (`?view=` compact or expanded, as the home page's,
      `IdejoWeb.TopicView`; `?show=` all or unread only; the Filter's hidden forums; each
      remembered in the session);
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
          communities: Community.communities(user),
          news: news(user)
        )

      _ ->
        redirect(conn, to: ~p"/users/sign-in")
    end
  end

  # Each forum's unread messages, by host: the topics the member follows there.
  defp news(user) do
    for entry <- Inbox.topics(user), reduce: %{} do
      acc -> Map.update(acc, entry.forum.host, entry.unread || 0, &(&1 + (entry.unread || 0)))
    end
  end

  def topics(conn, params) do
    {conn, view} = IdejoWeb.TopicView.choose(conn, params)
    {conn, show} = choose_show(conn, params)
    entries = Inbox.topics(conn.assigns.current_scope.user)

    forums =
      entries
      |> Enum.map(& &1.forum)
      |> Enum.uniq_by(& &1.host)
      |> Enum.sort_by(&String.downcase(&1.name))

    {conn, hidden} = choose_hidden(conn, params, forums)

    shown =
      for entry <- entries,
          entry.forum.host not in hidden,
          show == :all or entry.unread != nil,
          do: entry

    render(conn, :topics,
      page_title: gettext("Topics"),
      entries: shown,
      any?: entries != [],
      forums: forums,
      hidden: hidden,
      view: view,
      show: show
    )
  end

  # "Filter" (steward request, 2026-11-12): the forums whose topics are hidden, by host,
  # remembered in the session as `:inbox_hidden`. A submitted form (`filter=1`) hides every
  # listed forum not ticked; forums not listed now (no followed topic) stay as they were.
  defp choose_hidden(conn, %{"filter" => "1"} = params, forums) do
    ticked = List.wrap(params["forums"])
    listed = Enum.map(forums, & &1.host)
    kept = Enum.reject(remembered_hidden(conn), &(&1 in listed))
    hidden = kept ++ Enum.reject(listed, &(&1 in ticked))
    {put_session(conn, :inbox_hidden, hidden), hidden}
  end

  defp choose_hidden(conn, _params, _forums), do: {conn, remembered_hidden(conn)}

  defp remembered_hidden(conn) do
    case get_session(conn, :inbox_hidden) do
      hosts when is_list(hosts) -> Enum.filter(hosts, &is_binary/1)
      _ -> []
    end
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

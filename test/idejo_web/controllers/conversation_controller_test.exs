# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ConversationControllerTest do
  # Private conversations (steward decision, 2026-10-27).
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Conversations
  alias Idejo.Forum
  alias Idejo.Moderation

  setup %{conn: conn} do
    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    ada = user_fixture(%{display_name: "Ada"})
    bo = user_fixture(%{display_name: "Bo"})
    %{conn: log_in_user(conn, ada), ada: ada, bo: bo}
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

  test "the user card's Private Message opens the conversation", %{conn: conn, ada: ada, bo: bo} do
    card = doc(conn, ~p"/u/#{bo.id}")

    assert [_] =
             card
             |> LazyHTML.query(~s(form#private-message-form[action="/u/#{bo.id}/message"]))
             |> Enum.to_list()

    # Not on one's own card, nor for visitors.
    refute conn |> get(~p"/u/#{ada.id}") |> html_response(200) =~ "private-message-form"
    refute build_conn() |> get(~p"/u/#{bo.id}") |> html_response(200) =~ "private-message-form"

    conn = post(conn, ~p"/u/#{bo.id}/message")
    assert "/p/" <> id = redirected_to(conn)
    page = doc(recycle(conn), ~p"/p/#{id}")
    assert page |> LazyHTML.query("#topic-title") |> LazyHTML.text() =~ "Bo"
    assert [_] = page |> LazyHTML.query("#composer") |> Enum.to_list()
    # No slow mode: no timer line under the composer.
    assert page |> LazyHTML.query("#composer-timer") |> Enum.to_list() == []

    # The same conversation the second time.
    assert redirected_to(post(recycle(conn), ~p"/u/#{bo.id}/message")) == "/p/" <> id
  end

  test "no button, and no conversation, for someone who turned them off", %{conn: conn, bo: bo} do
    {:ok, _} = Accounts.update_user_private_messages(bo, %{"accepts_private_messages" => "false"})
    refute conn |> get(~p"/u/#{bo.id}") |> html_response(200) =~ "private-message-form"

    conn = post(conn, ~p"/u/#{bo.id}/message")
    assert redirected_to(conn) == ~p"/p"
    assert Conversations.list(bo) == []
  end

  test "only participants open it; its URI and permalinks lead there", %{
    conn: conn,
    ada: ada,
    bo: bo
  } do
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, message} = Forum.post_message(bo, topic, %{"body" => "Hello"})

    assert redirected_to(get(conn, ~p"/t/#{topic.id}")) == ~p"/p/#{topic.id}"

    assert redirected_to(get(conn, ~p"/m/#{message.id}")) ==
             ~p"/p/#{topic.id}?around=#{message.id}" <> "#message-#{message.id}"

    for outsider <- [user_fixture(), user_with_role_fixture(:administrator)] do
      conn = log_in_user(build_conn(), outsider)
      assert redirected_to(get(conn, ~p"/p/#{topic.id}")) == ~p"/"
      assert redirected_to(get(conn, ~p"/t/#{topic.id}")) == ~p"/"
      assert redirected_to(get(conn, ~p"/m/#{message.id}")) == ~p"/"
    end

    assert redirected_to(get(build_conn(), ~p"/p/#{topic.id}")) == ~p"/users/sign-in"
  end

  test "the list shows a card per conversation, and the sidebar links it at the bottom", %{
    conn: conn,
    ada: ada,
    bo: bo
  } do
    page = doc(conn, ~p"/p")
    assert [_] = page |> LazyHTML.query("#no-conversations") |> Enum.to_list()

    assert [_] =
             page
             |> LazyHTML.query(".sidebar-pinned a#conversations-sidebar-link[href='/p']")
             |> Enum.to_list()

    {:ok, topic} = Conversations.start(bo, ada)
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Are you there?"})

    page = doc(conn, ~p"/p")
    card = LazyHTML.query(page, "#conversation-#{topic.id}")
    assert LazyHTML.text(card) =~ "Bo"
    assert LazyHTML.text(card) =~ "Are you there?"
    assert LazyHTML.text(card) =~ "1 new"

    assert page |> LazyHTML.query("#conversations-sidebar-link .sidebar-count") |> LazyHTML.text() =~
             "1"

    # Opening it reads it.
    get(conn, ~p"/p/#{topic.id}")
    refute doc(conn, ~p"/p") |> LazyHTML.query(".sidebar-count") |> Enum.any?()
  end

  test "writing in it from the live page, with no slow mode", %{conn: conn, ada: ada, bo: bo} do
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, lv, _html} = live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    render_hook(lv, "commit", %{"body" => "Hi Bo", "break" => false})
    assert [%{state: "open"} = open] = Forum.list_messages(topic)
    assert render(lv) =~ "Ctrl+Enter, or Enter three times, starts a new message."
    refute render(lv) =~ ~s(id="composer-timer")

    render_hook(lv, "commit", %{"body" => "Hi Bo", "break" => true})
    assert [%{id: id, state: "closed"}] = Forum.list_messages(topic)
    assert id == open.id

    # An outsider sees nothing, and cannot write.
    {:ok, other, html} =
      live_isolated(log_in_user(build_conn(), user_fixture()), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    refute html =~ "Hi Bo"
    refute has_element?(other, "#composer")
  end

  test "the profile turns receiving private messages off and on", %{conn: conn, ada: ada} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    lv
    |> form("#private-form", private: %{accepts_private_messages: "false"})
    |> render_submit()

    refute Accounts.get_user(ada.id).accepts_private_messages

    lv
    |> form("#private-form", private: %{accepts_private_messages: "true"})
    |> render_submit()

    assert Accounts.get_user(ada.id).accepts_private_messages
  end

  @tag req: "MO-01"
  test "MO-01 the queue shows a reported private message without a link into it", %{
    ada: ada,
    bo: bo
  } do
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, message} = Forum.post_message(bo, topic, %{"body" => "Rude words"})
    {:ok, _} = Moderation.report_message(ada, message, %{"reason" => "Rude"})

    conn = log_in_user(build_conn(), user_with_role_fixture(:moderator))
    page = doc(conn, ~p"/moderation")
    item = LazyHTML.query(page, "#reported-#{message.id}")

    assert item |> LazyHTML.query("#reported-body-#{message.id}") |> LazyHTML.text() =~
             "Rude words"

    assert LazyHTML.text(item) =~ "in a private conversation"
    refute LazyHTML.to_html(item) =~ ~s(href="/m/#{message.id}")

    conn = post(conn, ~p"/moderation/reports/#{message.id}", %{"outcome" => "resolve"})
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "resolved"
  end

  @tag req: "MO-02"
  test "MO-02 a server moderator deletes a reported private message from the queue", %{
    conn: conn,
    ada: ada,
    bo: bo
  } do
    {:ok, topic} = Conversations.start(ada, bo)
    {:ok, message} = Forum.post_message(bo, topic, %{"body" => "Rude words"})
    {:ok, _} = Moderation.report_message(ada, message, %{"reason" => "Rude"})

    moderator = log_in_user(build_conn(), user_with_role_fixture(:moderator))

    assert [_] =
             moderator
             |> doc(~p"/moderation")
             |> LazyHTML.query("#delete-#{message.id}")
             |> Enum.to_list()

    moderator =
      post(moderator, ~p"/moderation/reports/#{message.id}", %{
        "outcome" => "delete",
        "note" => "Insults"
      })

    assert Phoenix.Flash.get(moderator.assigns.flash, :info) =~ "Message deleted"
    assert Forum.get_readable_message(ada, message.id).deleted_at

    # Gone from the queue; the participants see the placeholder.
    refute recycle(moderator) |> get(~p"/moderation") |> html_response(200) =~ "Rude words"
    {:ok, _lv, html} = live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})
    assert html =~ "Message deleted by a moderator"
    refute html =~ "Rude words"
  end

  test "the queue offers no delete for a topic's message, nor to others", %{ada: ada, bo: bo} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, public} = Forum.create_topic(bo, general, %{"title" => "Hi", "body" => "Hi"})
    {:ok, reply} = Forum.post_message(bo, public, %{"body" => "Rude"})
    {:ok, _} = Moderation.report_message(ada, reply, %{"reason" => "Rude"})

    moderator = log_in_user(build_conn(), user_with_role_fixture(:moderator))
    refute moderator |> get(~p"/moderation") |> html_response(200) =~ "delete-#{reply.id}"

    moderator = post(moderator, ~p"/moderation/reports/#{reply.id}", %{"outcome" => "delete"})
    assert Phoenix.Flash.get(moderator.assigns.flash, :error) =~ "could not be deleted"
    refute Forum.get_viewable_message(admin, reply.id).deleted_at
  end
end

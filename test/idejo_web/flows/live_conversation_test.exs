# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Flows.LiveConversationTest do
  @moduledoc """
  MVP §4, "Live conversation": steps 1-4 were the exit check of M3 (MVP §7); step 5, "New
  topic from this" (TP-09), came with M4 (steward decision).

  It drives the real topic page as members would: the author types in the composer and
  presses Enter or Ctrl+Enter (the `Composer` hook's `"commit"` push), another member replies
  meanwhile, and a visitor watches. What the hook does in the browser (sent text in higher
  contrast, unsent changes until Enter) is the hook's own; here we check what the server
  stores and what everyone sees.
  """
  use IdejoWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.Message
  alias Idejo.Repo

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)
  end

  defp open_topic(conn, topic) do
    # The topic page is a controller embedding TopicLive (live_render), whose first render is
    # in the page's HTML; once the browser connects, that view takes over.
    html = conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)
    assert html =~ topic.title
    assert html =~ ~s(id="topic-live")

    {:ok, lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    lv
  end

  defp enter(lv, body), do: press(lv, body, false)
  defp ctrl_enter(lv, body), do: press(lv, body, true)

  defp press(lv, body, break) do
    lv |> element("#composer") |> render_hook("commit", %{"body" => body, "break" => break})
    assert_reply(lv, reply)
    reply
  end

  defp items(lv) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#messages > li")
    |> LazyHTML.attribute("id")
  end

  defp text(lv, message),
    do:
      lv
      |> element("#message-#{message.id}-body")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()

  @tag flow: "live-conversation"
  test "a live conversation", %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Tonight", "body" => "Plans?"})

    [first] = Forum.list_messages(topic)

    ada = user_fixture(%{display_name: "Ada"})
    bo = user_fixture(%{display_name: "Bo"})
    author_conn = log_in_user(conn, ada)
    other_conn = log_in_user(build_conn(), bo)

    author = open_topic(author_conn, topic)
    visitor = open_topic(build_conn(), topic)

    # 1. Enter after a first line: the message appears for everyone, with ". " added; the
    #    sent text stays in the composer; the window (15 s by default) starts, unseen.
    assert enter(author, "Hello everyone") == %{closed: false, body: "Hello everyone."}

    message = Repo.get_by!(Message, topic_id: topic.id, state: "open")
    assert DateTime.diff(message.closes_at, message.opened_at) == 15
    assert text(visitor, message) =~ "Hello everyone."
    assert items(author) == ["message-#{first.id}", "message-#{message.id}"]
    refute author |> element("#composer") |> render() =~ ~r/\d+\s*s\b/
    assert visitor |> element("#topic-announcer") |> render() =~ "Ada started a message."

    # 2. Enter after each part joins the same message on the same line; Ctrl+Enter in the
    #    window continues on a new line of the same message.
    assert %{closed: false} = enter(author, "Hello everyone. Who is comming tonight?")

    assert %{closed: false} =
             ctrl_enter(author, "Hello everyone. Who is comming tonight?")

    assert %{closed: false} =
             enter(author, "Hello everyone. Who is comming tonight?\nI can bring snacks")

    assert [%{id: id, body_md: body}] =
             Repo.all(from m in Message, where: m.topic_id == ^topic.id and m.state == "open")

    assert id == message.id
    assert body == "Hello everyone. Who is comming tonight?\nI can bring snacks."
    assert text(visitor, message) =~ "I can bring snacks."

    #    Another member replies meanwhile: the reply appears below the author's composer,
    #    which keeps growing.
    other = open_topic(other_conn, topic)
    assert %{closed: false} = enter(other, "Me")

    reply =
      Repo.get_by!(Message, topic_id: topic.id, author_id: bo.id)

    assert items(author) ==
             ["message-#{first.id}", "message-#{message.id}", "message-#{reply.id}"]

    assert items(visitor) ==
             ["message-#{first.id}", "message-#{message.id}", "message-#{reply.id}"]

    assert %{closed: false} =
             enter(
               author,
               "Hello everyone. Who is comming tonight?\nI can bring snacks. And drinks"
             )

    assert text(visitor, message) =~ "And drinks."

    assert items(author) ==
             ["message-#{first.id}", "message-#{message.id}", "message-#{reply.id}"]

    refute has_element?(visitor, "#message-#{message.id}-versions")

    # 3. The author fixes a typo in an earlier line, in the composer: on Enter a discreet
    #    "view earlier version" tag appears, holding the old text.
    assert %{closed: false} =
             enter(
               author,
               "Hello everyone. Who is coming tonight?\nI can bring snacks. And drinks."
             )

    assert text(visitor, message) =~ "Who is coming tonight?"

    assert has_element?(
             visitor,
             "#message-#{message.id}-versions summary",
             "view earlier version"
           )

    assert has_element?(visitor, "#message-#{message.id}-versions", "Who is comming tonight?")

    # 4. The window ends (as if 15 s had gone by): the author is still in the same message and
    #    Enter still adds to it. Only now does Ctrl+Enter close it and start a new message.
    message
    |> Ecto.Changeset.change(closes_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    send(author.pid, {:window_ended, message.id})

    full = "Hello everyone. Who is coming tonight?\nI can bring snacks. And drinks. Anyone else?"
    assert %{closed: false} = enter(author, full)
    assert Repo.reload!(message).state == "open"
    assert text(visitor, message) =~ "Anyone else?"

    assert %{closed: true} = ctrl_enter(author, full)
    assert Repo.reload!(message).state == "closed"
    assert Repo.reload!(message).body_md == full
    assert visitor |> element("#topic-announcer") |> render() =~ "Ada’s message is complete."

    assert %{closed: false, body: "See you there."} = enter(author, "See you there")
    next = Repo.get_by!(Message, topic_id: topic.id, state: "open", author_id: ada.id)
    refute next.id == message.id

    assert items(author) == [
             "message-#{first.id}",
             "message-#{message.id}",
             "message-#{reply.id}",
             "message-#{next.id}"
           ]

    assert text(visitor, next) =~ "See you there."

    # The conversation reads like a forum: four messages, each one item (GM-13).
    assert Repo.reload!(topic).message_count == 4
    assert length(Forum.list_messages(topic)) == 4
    assert Messages.list_versions(message) |> length() == 1

    # 5. A side question comes up: Bo selects Ada's message and chooses "New topic from
    #    this"; the new topic links back to it.
    assert has_element?(other, "#message-#{message.id}-fork", "New topic from this")
    {:ok, fork_lv, _html} = live(other_conn, ~p"/m/#{message.id}/new-topic")
    assert has_element?(fork_lv, ~s(#forked-from a[href="/m/#{message.id}"]))

    {:ok, fork_conn} =
      fork_lv
      |> form("#new-topic-form", topic: %{title: "Snacks", body: "Sweet or salty?"})
      |> render_submit()
      |> follow_redirect(other_conn)

    fork = Repo.get_by!(Forum.Topic, title: "Snacks")
    assert fork.forked_from_message_id == message.id
    assert fork.category_id == general.id

    fork_page = html_response(fork_conn, 200)
    assert fork_page =~ ~s(href="/m/#{message.id}")
    assert fork_page =~ "Continued from Ada in “Tonight”"

    assert has_element?(
             visitor,
             ~s(#message-#{message.id}-forks a[href="/t/#{fork.id}/#{fork.slug}"][aria-label="Continue topic: Snacks"]),
             "Continue topic"
           )
  end
end

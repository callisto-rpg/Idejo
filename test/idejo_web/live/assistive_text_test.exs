# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AssistiveTextTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Repo

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    author = user_fixture(%{display_name: "Ada"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{conn: log_in_user(conn, author), topic: topic, author: author}
  end

  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  defp announcer(lv), do: lv |> element("#topic-announcer") |> render()

  defp announcement_id(lv) do
    lv
    |> announcer()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#topic-announcer > span")
    |> LazyHTML.attribute("id")
  end

  defp end_window!(message) do
    message
    |> Ecto.Changeset.change(closes_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update!()
  end

  @tag req: "AX-02"
  test "AX-02 a growing message is announced when it opens and when it closes, not at appends",
       %{topic: topic, author: author} do
    {:ok, reader, _html} = watch(build_conn(), topic)

    assert has_element?(reader, "#topic-announcer[role=status][aria-live=polite]")
    # The list itself is not a live region, so appends are not read out.
    refute render(reader) =~ ~r/<ol id="messages"[^>]*aria-live/

    {:ok, open} = Messages.commit(author, topic, "Hello")
    assert announcer(reader) =~ "Ada started a message."
    opened = announcement_id(reader)

    {:ok, _} = Messages.commit(author, topic, "Hello. How are you")
    {:ok, _} = Messages.commit(author, topic, "Hello. How are you all")
    assert render(reader) =~ "How are you all."
    assert announcement_id(reader) == opened
    assert announcer(reader) =~ "Ada started a message."

    {:ok, _} = Messages.close(open)
    assert announcer(reader) =~ "Ada’s message is complete."
    refute announcer(reader) =~ "How are you"
  end

  @tag req: "AX-02"
  test "AX-02 a message posted closed is announced once; the same words twice are read twice",
       %{topic: topic} do
    {:ok, reader, _html} = watch(build_conn(), topic)
    bob = user_fixture(%{display_name: "Bob"})

    {:ok, _} = Forum.post_message(bob, topic, %{"body" => "One"})
    assert announcer(reader) =~ "New message from Bob."
    first = announcement_id(reader)

    {:ok, _} = Forum.post_message(bob, topic, %{"body" => "Two"})
    assert announcer(reader) =~ "New message from Bob."
    refute announcement_id(reader) == first
  end

  @tag req: "AX-02"
  test "AX-02 the author hears their own message open and close", %{conn: conn, topic: topic} do
    {:ok, lv, _html} = watch(conn, topic)

    lv |> element("#composer") |> render_hook("commit", %{"body" => "Hi", "break" => false})
    assert announcer(lv) =~ "You started a message."

    [_, open] = Forum.list_messages(topic)
    end_window!(open)
    lv |> element("#composer") |> render_hook("commit", %{"body" => "Hi.", "break" => true})
    assert announcer(lv) =~ "Your message is complete."
  end

  @tag req: "AX-03"
  test "AX-03 the open state is text for assistive technology only", %{
    topic: topic,
    author: author
  } do
    {:ok, open} = Messages.commit(author, topic, "Hello")
    {:ok, reader, html} = watch(build_conn(), topic)

    for page <- [html, render(reader)] do
      assert page =~ "(still being written)"
    end

    assert has_element?(reader, "#message-#{open.id}-author .sr-only", "(still being written)")

    {:ok, _} = Messages.close(open)
    refute render(reader) =~ "(still being written)"
  end

  @tag req: "AX-03"
  test "AX-03 the composer is described by the time left in the window", %{
    conn: conn,
    topic: topic,
    author: author
  } do
    {:ok, lv, _html} = watch(conn, topic)
    assert has_element?(lv, "#composer textarea[aria-describedby=composer-window]")
    assert has_element?(lv, "#composer-window.sr-only", "Enter starts a new message.")

    {:ok, open} = Messages.commit(author, topic, "Hello")
    text = lv |> element("#composer-window") |> render()
    assert text =~ "Your message is open."
    assert [_, left] = Regex.run(~r/Ctrl\+Enter starts a new message in (\d+) seconds?\./, text)
    assert String.to_integer(left) in 40..45

    # As if 45 s had gone by: the next append carries the past closes_at, and the server
    # re-renders on its ticks and on the window_ended event.
    end_window!(open)
    {:ok, _} = Messages.commit(author, topic, "Hello. Still here")
    send(lv.pid, {:window_ended, open.id})
    assert lv |> element("#composer-window") |> render() =~ "Ctrl+Enter starts a new message."
    refute lv |> element("#composer-window") |> render() =~ "seconds"
  end

  @tag req: "AX-03"
  test "AX-03 the view earlier version tag is text", %{conn: conn, topic: topic, author: author} do
    {:ok, open} = Messages.commit(author, topic, "Meet on Monday")
    {:ok, closed} = Messages.close(open)
    {:ok, _} = Messages.edit(author, closed, "Meet on Tuesday.")

    {:ok, lv, _html} = watch(conn, topic)

    assert has_element?(
             lv,
             "#message-#{closed.id}-versions > summary",
             "view earlier version"
           )

    assert has_element?(lv, "#message-#{closed.id}-versions time[datetime]")
  end
end

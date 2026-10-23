# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ComposerTest do
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

  defp enter(lv, body, break \\ false) do
    lv |> element("#composer") |> render_hook("commit", %{"body" => body, "break" => break})
  end

  defp items(lv) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#messages > li")
    |> LazyHTML.attribute("id")
  end

  @tag req: "GM-07"
  test "GM-07 the composer is only a text box whose placeholder names the keys", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    composer = lv |> element("#composer") |> render()

    assert composer =~
             "Enter · send | Shift+Enter · new line | Ctrl+Enter or Enter ×3 · new message"

    assert composer =~ "<textarea"
    refute composer =~ "<button"
    refute composer =~ ~r/\d+\s*s\b/
  end

  @tag req: "GM-01"
  test "GM-01 Enter in the composer opens a message for everyone", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    {:ok, reader, _html} = watch(build_conn(), topic)

    enter(lv, "Hello")
    assert_reply(lv, %{closed: false, body: "Hello."})

    [_, message] = Forum.list_messages(topic)
    assert message.state == "open"
    assert has_element?(reader, "#message-#{message.id}", "Hello.")
  end

  @tag req: "GM-08"
  test "GM-08 the composer sits in place of the author's open message, replies below it", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    [first] = Forum.list_messages(topic)

    # With nothing open, the composer is at the end.
    assert items(lv) == ["message-#{first.id}", "composer-slot"]

    enter(lv, "Mine")
    [_, mine] = Forum.list_messages(topic)
    {:ok, reply} = Messages.commit(user_fixture(), topic, "Someone answers")

    # The composer is the open message, under the author's name; the reply comes below.
    assert items(lv) == ["message-#{first.id}", "message-#{mine.id}", "message-#{reply.id}"]
    assert has_element?(lv, "#message-#{mine.id} #composer")
    assert has_element?(lv, "#message-#{mine.id}", "Ada")

    # Appends keep it there.
    enter(lv, "Mine. Still mine")
    assert items(lv) == ["message-#{first.id}", "message-#{mine.id}", "message-#{reply.id}"]
  end

  @tag req: "GM-07"
  test "GM-07 readers see an open message like a closed one", %{conn: conn, topic: topic} do
    # The open state exists only as hidden text for assistive technology (AX-03), so that is
    # the one difference allowed.
    {:ok, lv, _html} = watch(conn, topic)
    {:ok, reader, _html} = watch(build_conn(), topic)

    enter(lv, "Same look")
    [first, open] = Forum.list_messages(topic)

    shape = fn id ->
      reader
      |> element("#message-#{id}")
      |> render()
      |> String.replace(~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "ID")
      |> String.replace(~r/<time.*?<\/time>/s, "TIME")
      |> String.replace(~r/<div[^>]*class="message-body"[^>]*>.*?<\/div>/s, "BODY")
      |> String.replace(~r/<a [^>]*class="author-name[^"]*">.*?<\/a>/s, "NAME")
      |> String.replace(~r/<span class="sr-only">.*?<\/span>/s, "")
    end

    assert shape.(open.id) == shape.(first.id)
    assert has_element?(reader, "#message-#{open.id} .sr-only", "(still being written)")
  end

  @tag req: "GM-05"
  test "GM-05 Ctrl+Enter after the window closes the message and the composer goes to the end",
       %{conn: conn, topic: topic} do
    {:ok, lv, _html} = watch(conn, topic)
    enter(lv, "Done")
    [_, mine] = Forum.list_messages(topic)

    mine
    |> Ecto.Changeset.change(closes_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    # Someone answered (else the unanswered message time applies).
    {:ok, _} = Idejo.Messages.commit(user_fixture(), topic, "Ok")
    enter(lv, "Done. Bye", true)
    assert_reply(lv, %{closed: true})

    assert Repo.reload!(mine).state == "closed"
    assert List.last(items(lv)) == "composer-slot"
    assert has_element?(lv, "#message-#{mine.id}", "Done. Bye.")
  end

  @tag req: "GM-05"
  test "GM-05 Ctrl+Enter within the window keeps the message open", %{conn: conn, topic: topic} do
    {:ok, lv, _html} = watch(conn, topic)
    enter(lv, "First line", true)
    assert_reply(lv, %{closed: false, body: "First line."})
  end

  # Steward decision, 2026-10-23: the line under the composer runs to when Ctrl+Enter may start
  # a new message: the unanswered message time alone, the window once someone wrote below.
  @tag req: "GM-05"
  test "GM-05 the line under the composer shows the time left before Ctrl+Enter works", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    refute has_element?(lv, "#composer-timer")
    enter(lv, "Thinking aloud")
    [_, mine] = Forum.list_messages(topic)

    ends = fn ->
      [value] =
        lv
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#composer-timer[phx-hook=ComposerTimer][aria-hidden=true]")
        |> LazyHTML.attribute("data-end")

      value |> String.to_integer() |> DateTime.from_unix!(:millisecond)
    end

    assert_in_delta DateTime.diff(ends.(), mine.opened_at, :millisecond), 600_000, 1

    {:ok, _} = Idejo.Messages.commit(user_fixture(), topic, "Go on")
    assert_in_delta DateTime.diff(ends.(), mine.opened_at, :millisecond), 15_000, 1

    # Complete: the line goes with the open message.
    Idejo.Messages.close(mine)
    _ = render(lv)
    refute has_element?(lv, "#composer-timer")
  end

  # Steward decision, 2026-10-23: the unanswered message time.
  @tag req: "GM-05"
  test "GM-05 alone below the last message, Ctrl+Enter after the window keeps it open", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    enter(lv, "Thinking aloud")
    [_, mine] = Forum.list_messages(topic)

    mine
    |> Ecto.Changeset.change(closes_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    enter(lv, "Thinking aloud. More", true)
    assert_reply(lv, %{closed: false, body: "Thinking aloud. More."})
    assert Repo.reload!(mine).state == "open"
  end

  @tag req: "GM-05"
  test "GM-05 three Enters in a row work as Ctrl+Enter, on touch screens too" do
    js = File.read!("assets/js/composer.js")
    assert js =~ "const ENTER_RUN = 3"
    assert js =~ "const ENTER_RUN_MS = 1000"
    # Every Enter counts, whatever the device; typing in between starts the count again.
    assert js =~ "this.send(e.ctrlKey || e.metaKey || this.enterRun())"
    assert js =~ ~r/addEventListener\("input", \(\) => \{\s*this.enters = 0/
    refute js =~ "No Ctrl+Enter on touch screens"
  end

  @tag req: "GM-02"
  test "GM-02 the server's text is the reply the composer keeps", %{conn: conn, topic: topic} do
    {:ok, lv, _html} = watch(conn, topic)
    enter(lv, "```\ncode")
    assert_reply(lv, %{closed: false, body: "```\ncode"})
  end

  @tag req: "GM-12"
  test "GM-12 after a reload the composer holds the open message again", %{
    conn: conn,
    topic: topic,
    author: author
  } do
    {:ok, _} = Messages.commit(author, topic, "Half a thought")
    html = conn |> get(~p"/t/#{topic.id}/chat") |> html_response(200)
    assert html =~ ~s(data-sent="Half a thought.")

    {:ok, lv, _html} = watch(conn, topic)
    assert_push_event(lv, "composer_sent", %{body: "Half a thought."})
  end

  @tag req: "GM-01"
  test "GM-01 a refused commit tells the composer", %{conn: conn, topic: topic} do
    {:ok, lv, _html} = watch(conn, topic)
    topic |> Ecto.Changeset.change(state: "locked") |> Repo.update!()

    enter(lv, "Too late")
    assert_reply(lv, %{error: true})
    refute has_element?(lv, "#composer")
  end

  @tag req: "GM-07"
  test "GM-07 the composer has no box: sent text reads as a message, unsent text is highlighted, text just sent burns in" do
    css = File.read!("assets/css/app.css")
    [composer] = Regex.run(~r/^\.composer \{.*?^\}/ms, css)
    refute composer =~ ~r/border:|background:/
    assert css =~ ~r/\.composer-unsent \{[^}]*box-shadow/s
    assert css =~ "@keyframes composer-burn"
    # White in a golden glow on the light theme, bright orange on the dark one.
    assert css =~ ~r/\.composer-burn \{\s*--burn-ink: #ffffff;\s*--burn-gold:/
    assert css =~ ~r/\[data-theme="dark"\] \.composer-burn \{ --burn-ink: oklch/
    assert css =~ ~r/prefers-reduced-motion: reduce\) \{\s*\.composer-burn \{ animation: none; \}/

    js = File.read!("assets/js/composer.js")
    assert js =~ "composer-burn"
    assert js =~ "export function burnMarks"
    # Repaints keep the burn's place through the DOM, never a style attribute (SP-05).
    assert js =~ "style.animationDelay"
  end
end

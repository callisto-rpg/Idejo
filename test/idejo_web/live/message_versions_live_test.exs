# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MessageVersionsLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages

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

    {:ok, open} = Messages.commit(author, topic, "Meet on Monday")
    {:ok, closed} = Messages.close(open)
    %{conn: log_in_user(conn, author), topic: topic, author: author, closed: closed}
  end

  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  # What the Composer hook sends on Enter (Ctrl+Enter with `break`).
  defp enter(lv, body, break? \\ false),
    do: lv |> element("#composer") |> render_hook("commit", %{"body" => body, "break" => break?})

  # Steward decision, 2026-10-24: Edit puts the composer in the message, as it was written.
  @tag req: "GM-10"
  test "GM-10 the author edits a closed message in the composer, and readers see it", %{
    conn: conn,
    topic: topic,
    closed: closed
  } do
    {:ok, lv, _html} = watch(conn, topic)
    {:ok, reader, _html} = watch(build_conn(), topic)

    refute has_element?(reader, "#message-#{closed.id} button", "Edit")
    lv |> element("#message-#{closed.id} button", "Edit") |> render_click()

    # The composer is the message, in place, with no timer; the text comes back to the box.
    assert has_element?(lv, "#message-#{closed.id} #composer[data-editing]")
    refute has_element?(lv, "#composer-timer")
    assert_push_event(lv, "composer_sent", %{body: "Meet on Monday."})
    assert has_element?(lv, "#composer-window", "You are editing your message.")

    # Enter saves, and readers see each one, like a growing message.
    enter(lv, "Meet on Monday. Bring tea.")
    assert Idejo.Repo.get!(Messages.Message, closed.id).body_md == "Meet on Monday. Bring tea."
    assert has_element?(reader, "#message-#{closed.id}", "Meet on Monday. Bring tea.")
    assert Idejo.Repo.get!(Messages.Message, closed.id).state == "closed"

    # Ctrl+Enter, at any time, saves and ends the edit: the composer goes back to the end.
    enter(lv, "Meet on Tuesday. Bring tea.", true)
    refute has_element?(lv, "#message-#{closed.id} #composer")
    assert has_element?(lv, "#composer-slot #composer")
    assert_push_event(lv, "composer_sent", %{body: ""})
    assert has_element?(reader, "#message-#{closed.id}", "Meet on Tuesday. Bring tea.")
  end

  @tag req: "GM-11"
  test "GM-11 an edit in the composer keeps one version, however many Enters", %{
    conn: conn,
    topic: topic,
    closed: closed
  } do
    {:ok, lv, _html} = watch(conn, topic)
    lv |> element("#message-#{closed.id} button", "Edit") |> render_click()

    enter(lv, "Meet on Monday. At noon")
    enter(lv, "Meet on Monday. At noon. Bring tea")
    enter(lv, "Meet on Tuesday. At noon. Bring tea", true)

    message = Idejo.Repo.get!(Messages.Message, closed.id) |> Idejo.Repo.preload(:versions)
    assert message.edited
    assert Enum.map(message.versions, & &1.body_md) == ["Meet on Monday."]

    # A second edit keeps the text the first one left.
    lv |> element("#message-#{closed.id} button", "Edit") |> render_click()
    enter(lv, "Meet on Tuesday. At one. Bring tea", true)

    versions = Idejo.Repo.preload(message, :versions, force: true).versions

    assert versions |> Enum.map(& &1.body_md) |> Enum.sort() ==
             ["Meet on Monday.", "Meet on Tuesday. At noon. Bring tea"]

    # Ending an edit with nothing changed keeps nothing.
    lv |> element("#message-#{closed.id} button", "Edit") |> render_click()
    enter(lv, "Meet on Tuesday. At one. Bring tea", true)
    assert length(Idejo.Repo.preload(message, :versions, force: true).versions) == 2
  end

  @tag req: "GM-10"
  test "GM-10 an emptied edit asks to delete the message; No keeps it", %{
    conn: conn,
    topic: topic,
    closed: closed
  } do
    {:ok, lv, _html} = watch(conn, topic)
    lv |> element("#message-#{closed.id} button", "Edit") |> render_click()

    enter(lv, "")

    assert has_element?(
             lv,
             "dialog#delete-own-dialog",
             "Are you sure you want to delete your own message?"
           )

    # "No" closes the dialog natively, which sends its close event: still editing.
    lv |> element("#delete-own-dialog") |> render_hook("cancel_delete_own", %{})
    refute has_element?(lv, "#delete-own-dialog")
    assert has_element?(lv, "#message-#{closed.id} #composer[data-editing]")

    enter(lv, "Meet on Monday.", true)
    assert has_element?(lv, "#message-#{closed.id}", "Meet on Monday.")
  end

  @tag req: "GM-11"
  test "GM-11 an edited message shows a discreet tag opening every earlier version", %{
    conn: conn,
    topic: topic,
    author: author,
    closed: closed
  } do
    {:ok, lv, _html} = watch(build_conn(), topic)
    refute has_element?(lv, "#message-#{closed.id}-versions")

    {:ok, _} = Messages.edit(author, closed, "Meet on Tuesday.")
    {:ok, _} = Messages.edit(author, closed, "Meet on Wednesday.")

    versions = lv |> element("#message-#{closed.id}-versions") |> render()
    assert versions =~ "view earlier version"
    assert versions =~ "Meet on Monday."
    assert versions =~ "Meet on Tuesday."
    assert length(Regex.scan(~r/<time /, versions)) == 4

    # Newest first; it opens without JavaScript (a <details> element in the page's HTML).
    assert :binary.match(versions, "Tuesday") < :binary.match(versions, "Monday")
    html = conn |> get(~p"/t/#{topic.id}/chat") |> html_response(200)
    assert html =~ ~r/<details[^>]* id="message-#{closed.id}-versions"/
  end

  @tag req: "GM-11"
  test "GM-11 a message that only grew shows no tag", %{topic: topic, author: author} do
    {:ok, _} = Messages.commit(author, topic, "One")
    {:ok, open} = Messages.commit(author, topic, "One. Two")

    {:ok, lv, _html} = watch(build_conn(), topic)
    refute has_element?(lv, "#message-#{open.id}-versions")
  end
end

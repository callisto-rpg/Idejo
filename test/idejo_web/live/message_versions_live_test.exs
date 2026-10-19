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

  @tag req: "GM-10"
  test "GM-10 the author edits a closed message from the topic, and readers see it", %{
    conn: conn,
    topic: topic,
    closed: closed
  } do
    {:ok, lv, _html} = watch(conn, topic)
    {:ok, reader, _html} = watch(build_conn(), topic)

    refute has_element?(reader, "#message-#{closed.id} button", "Edit")
    lv |> element("#message-#{closed.id} button", "Edit") |> render_click()
    assert has_element?(lv, "#edit-message-#{closed.id} textarea", "Meet on Monday.")

    lv
    |> form("#edit-message-#{closed.id}", edit: %{body: "Meet on Tuesday."})
    |> render_submit()

    refute has_element?(lv, "#edit-message-#{closed.id}")
    assert has_element?(reader, "#message-#{closed.id}", "Meet on Tuesday.")
  end

  @tag req: "GM-10"
  test "GM-10 an empty edit is refused, and editing can be cancelled", %{
    conn: conn,
    topic: topic,
    closed: closed
  } do
    {:ok, lv, _html} = watch(conn, topic)
    lv |> element("#message-#{closed.id} button", "Edit") |> render_click()

    assert lv |> form("#edit-message-#{closed.id}", edit: %{body: " "}) |> render_submit() =~
             "can&#39;t be blank"

    lv |> element("#edit-message-#{closed.id} button", "Cancel") |> render_click()
    refute has_element?(lv, "#edit-message-#{closed.id}")
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

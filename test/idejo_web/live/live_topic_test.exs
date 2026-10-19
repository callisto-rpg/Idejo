# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.LiveTopicTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, topic: topic, member: user_fixture(%{display_name: "Mia"})}
  end

  # What the topic page embeds, as a visitor (`conn` without a session) or a member.
  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  defp ids(lv) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#messages > li")
    |> LazyHTML.attribute("id")
  end

  @tag req: "TP-04"
  test "TP-04 a new message reaches every viewer live", %{
    conn: conn,
    topic: topic,
    member: member
  } do
    {:ok, visitor, _html} = watch(conn, topic)
    {:ok, other, _html} = watch(log_in_user(build_conn(), user_fixture()), topic)

    {:ok, message} = Forum.post_message(member, topic, %{"body" => "Fresh **news**"})

    for lv <- [visitor, other] do
      assert render(lv) =~ "<strong>news</strong>"
      assert has_element?(lv, "#message-#{message.id}", "Mia")
    end
  end

  @tag req: "TP-04"
  test "TP-04 appends to a growing message appear in place", %{
    conn: conn,
    topic: topic,
    member: member
  } do
    {:ok, lv, _html} = watch(conn, topic)

    {:ok, growing} = Messages.commit(member, topic, "First line")
    {:ok, reply} = Forum.post_message(user_fixture(), topic, %{"body" => "A reply"})
    {:ok, _} = Messages.commit(member, topic, "First line. And more")

    assert has_element?(lv, "#message-#{growing.id}", "First line. And more.")
    # Still one element, still in its place above the reply (GM-08).
    assert Enum.take(ids(lv), -2) == ["message-#{growing.id}", "message-#{reply.id}"]
    assert length(ids(lv)) == 3
  end

  @tag req: "TP-04"
  test "TP-04 after a reconnect the viewer catches up on what was missed", %{
    conn: conn,
    topic: topic,
    member: member
  } do
    # The connection drops: the view's process is gone (the test survives it).
    Process.flag(:trap_exit, true)
    {:ok, lv, _html} = watch(conn, topic)
    ref = Process.monitor(lv.pid)
    Process.exit(lv.pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}

    {:ok, missed} = Forum.post_message(member, topic, %{"body" => "While you were away"})

    # Reconnecting mounts the view again, which loads the messages afresh.
    {:ok, lv, _html} = watch(conn, topic)
    assert has_element?(lv, "#message-#{missed.id}", "While you were away")
  end

  @tag req: "TP-04"
  test "TP-04 the first render holds the messages, for readers without JavaScript", %{
    conn: conn,
    topic: topic,
    member: member
  } do
    {:ok, message} = Forum.post_message(member, topic, %{"body" => "Readable"})
    html = conn |> get(~p"/t/#{topic.id}/chat") |> html_response(200)

    assert html =~ ~s(id="message-#{message.id}")
    assert html =~ "Readable"
  end

  @tag req: "TP-04"
  test "TP-04 a viewer who loses the view right stops seeing the topic when the grid changes",
       %{conn: conn, admin: admin, general: general, topic: topic, member: member} do
    {:ok, lv, _html} = watch(conn, topic)
    assert length(ids(lv)) == 1

    guest = Access.built_in_role!(:guest)
    {:ok, _} = Access.set_permission(admin, guest, general, :view, :deny)

    assert has_element?(lv, "#topic-gone", "You can no longer view this topic.")
    assert ids(lv) == []

    # No more events reach it.
    {:ok, _} = Forum.post_message(member, topic, %{"body" => "Secret now"})
    refute render(lv) =~ "Secret now"
  end

  @tag req: "TP-04"
  test "TP-04 a poster who loses the post right loses the form when the grid changes", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic,
    member: member
  } do
    {:ok, lv, _html} = watch(log_in_user(conn, member), topic)
    assert has_element?(lv, "#message-form")

    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), general, :post, :deny)
    refute has_element?(lv, "#message-form")
    assert length(ids(lv)) == 1
  end

  @tag req: "TP-04"
  test "TP-04 a topic the viewer may not view shows nothing", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic
  } do
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), general, :view, :deny)
    {:ok, lv, _html} = watch(conn, topic)
    assert ids(lv) == []
    refute render(lv) =~ "Hi"
  end
end

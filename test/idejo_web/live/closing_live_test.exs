# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ClosingLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.Authors
  alias Idejo.Repo

  setup do
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

    %{topic: topic, author: author}
  end

  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  @tag req: "GM-12"
  test "GM-12 a live topic view keeps its user present", %{topic: topic, author: author} do
    refute Authors.present?(topic.id, author.id)
    {:ok, _lv, _html} = watch(log_in_user(build_conn(), author), topic)
    assert Authors.present?(topic.id, author.id)
  end

  @tag req: "GM-12"
  test "GM-12 when the message closed while away, the composer is told nothing is open", %{
    topic: topic,
    author: author
  } do
    {:ok, open} = Messages.commit(author, topic, "Gone a while")
    {:ok, _} = Messages.close(open)

    {:ok, lv, _html} = watch(log_in_user(build_conn(), author), topic)
    assert_push_event(lv, "composer_sent", %{body: ""})
  end

  @tag req: "GM-16"
  test "GM-16 a moderator closes another user's open message from the topic", %{
    topic: topic,
    author: author
  } do
    {:ok, open} = Messages.commit(author, topic, "Going on and on")
    moderator = user_with_role_fixture(:moderator)

    {:ok, member_view, _html} = watch(log_in_user(build_conn(), user_fixture()), topic)
    refute has_element?(member_view, "#message-#{open.id} button", "Close message")

    {:ok, lv, _html} = watch(log_in_user(build_conn(), moderator), topic)
    assert has_element?(lv, "#message-#{open.id}-moderate-form button", "Close message")

    # With an optional reason for the moderation log (MO-03).
    lv
    |> form("#message-#{open.id}-moderate-form", %{"reason" => "Left open"})
    |> render_submit(%{"do" => "close"})

    assert Repo.reload!(open).state == "closed"
    refute has_element?(lv, "#message-#{open.id} button", "Close message")
    assert Repo.one!(Idejo.Moderation.Action).reason == "Left open"
  end

  @tag req: "GM-16"
  test "GM-16 moderators see no Close button on their own or closed messages", %{
    topic: topic
  } do
    moderator = user_with_role_fixture(:moderator)
    {:ok, own} = Messages.commit(moderator, topic, "Mine")
    [first | _] = Forum.list_messages(topic)

    {:ok, lv, _html} = watch(log_in_user(build_conn(), moderator), topic)
    refute has_element?(lv, "button", "Close message")
    assert has_element?(lv, "#message-#{own.id} #composer")
    assert has_element?(lv, "#message-#{first.id}")
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SidebarDotsTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    me = user_fixture(%{display_name: "Me"})
    {:ok, topic} = Forum.create_topic(me, general, %{"title" => "Picnic", "body" => "Saturday?"})
    [mine] = Forum.list_messages(topic)
    :ok = Reading.mark_read(me, topic)
    %{admin: admin, general: general, me: me, topic: topic, mine: mine}
  end

  defp level(me, topic), do: Reading.activity(me, [topic.id])[topic.id]

  test "a followed topic: grey for new messages, orange for a reply, red for a mention", %{
    admin: admin,
    me: me,
    topic: topic,
    mine: mine
  } do
    assert level(me, topic) == nil

    {:ok, _} = Forum.post_message(user_fixture(), topic, %{"body" => "Count me in"})
    assert level(me, topic) == :new

    {:ok, _} =
      Forum.post_message(user_fixture(), topic, %{"body" => "Yes", "reply_to_id" => mine.id})

    assert level(me, topic) == :reply

    {:ok, _} = Forum.post_message(user_fixture(), topic, %{"body" => "Ask @#{me.username}"})
    assert level(me, topic) == :mention

    # Opening the topic reads it all.
    :ok = Reading.mark_read(me, topic)
    assert level(me, topic) == nil

    # A +role mention counts as a mention.
    {:ok, crew} =
      Access.create_role(admin, %{"name" => unique_role_name("Crew"), "mentionable" => "true"})

    :ok = Access.grant_role(me, crew)

    {:ok, _} =
      Forum.post_message(user_fixture(), topic, %{"body" => "Hey +#{Access.role_slug(crew)}"})

    assert level(me, topic) == :mention
  end

  test "the sidebar draws the dot and a stronger name, with words for screen readers", %{
    me: me,
    topic: topic,
    mine: mine
  } do
    {:ok, _} =
      Forum.post_message(user_fixture(), topic, %{"body" => "Yes", "reply_to_id" => mine.id})

    html = build_conn() |> log_in_user(me) |> get(~p"/c/general") |> html_response(200)
    doc = LazyHTML.from_document(html)

    assert doc
           |> LazyHTML.query("#sidebar .sidebar-topic.has-news .sidebar-dot.is-reply")
           |> Enum.count() == 1

    assert doc |> LazyHTML.query("#sidebar .sidebar-topic-link .sr-only") |> LazyHTML.text() =~
             "a reply to you"

    :ok = Reading.mark_read(me, topic)
    html = build_conn() |> log_in_user(me) |> get(~p"/c/general") |> html_response(200)
    refute html =~ "has-news"
  end
end

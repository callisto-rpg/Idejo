# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UnreadBadgeTest do
  @moduledoc """
  The dot on the header's Unread link (steward decision, 2026-10-23): how many unread
  messages reply to the user or mention them or their roles, in the sidebar dots' colours.
  """
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
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

  defp post!(topic, attrs) do
    {:ok, message} = Forum.post_message(user_fixture(), topic, attrs)
    message
  end

  test "counts unread replies, @mentions and +role mentions; the strongest sets the colour", %{
    admin: admin,
    me: me,
    topic: topic,
    mine: mine
  } do
    assert Reading.for_you(me) == %{count: 0, level: nil}

    # New messages in a followed topic are not counted.
    post!(topic, %{"body" => "Count me in"})
    assert Reading.for_you(me) == %{count: 0, level: nil}

    {:ok, crew} =
      Access.create_role(admin, %{"name" => unique_role_name("Crew"), "mentionable" => "true"})

    :ok = Access.grant_role(me, crew)
    post!(topic, %{"body" => "Hey +#{Access.role_slug(crew)}"})
    assert Reading.for_you(me) == %{count: 1, level: :role_mention}

    post!(topic, %{"body" => "Yes", "reply_to_id" => mine.id})
    assert Reading.for_you(me) == %{count: 2, level: :reply}

    rude = post!(topic, %{"body" => "Ask @#{me.username}"})
    assert Reading.for_you(me) == %{count: 3, level: :mention}

    # A deleted message no longer counts; opening the topic reads them all.
    {:ok, _} = Messages.delete_as_moderator(user_with_role_fixture(:moderator), rude)
    assert Reading.for_you(me) == %{count: 2, level: :reply}

    :ok = Reading.mark_read(me, topic)
    assert Reading.for_you(me) == %{count: 0, level: nil}
    assert Reading.for_you(nil) == %{count: 0, level: nil}
  end

  test "topics the user may no longer view are not counted", %{
    admin: admin,
    general: general,
    me: me,
    topic: topic
  } do
    post!(topic, %{"body" => "Ask @#{me.username}"})
    assert Reading.for_you(me).count == 1

    for role <- [:member, :guest],
        do:
          {:ok, _} =
            Access.set_permission(admin, Access.built_in_role!(role), general, :view, :deny)

    assert Reading.for_you(me).count == 0
  end

  test "the header's Unread link shows the dot, and /sidebar serves it for the live update", %{
    me: me,
    topic: topic,
    mine: mine
  } do
    conn = log_in_user(build_conn(), me)
    refute conn |> get(~p"/") |> html_response(200) =~ "unread-badge"

    post!(topic, %{"body" => "Yes", "reply_to_id" => mine.id})

    badge =
      conn
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#unread-link .header-badge.unread-badge.is-reply")

    assert badge |> LazyHTML.text() |> String.trim() == "1 reply or mention for you"

    sidebar = conn |> get(~p"/sidebar") |> html_response(200) |> LazyHTML.from_fragment()
    assert sidebar |> LazyHTML.query("#unread-link .unread-badge.is-reply") |> Enum.count() == 1
    assert sidebar |> LazyHTML.query("aside#sidebar") |> Enum.count() == 1
  end
end

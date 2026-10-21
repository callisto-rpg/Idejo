# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicModerationTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Plans", "body" => "Hi"})

    %{topic: topic}
  end

  defp page(conn, topic), do: conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)

  @tag req: "TP-14"
  test "TP-14 moderators lock and pin from the topic page, without JavaScript", %{topic: topic} do
    moderator = log_in_user(build_conn(), user_with_role_fixture(:moderator))
    member = log_in_user(build_conn(), user_fixture())

    assert page(moderator, topic) =~ ~s(id="topic-moderation-form")
    refute page(member, topic) =~ "topic-moderation-form"
    refute page(build_conn(), topic) =~ "topic-moderation-form"

    # A member's composer goes away live when the topic is locked.
    {:ok, lv, _html} =
      live_isolated(member, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    assert has_element?(lv, "#composer")

    conn = post(moderator, ~p"/t/#{topic.id}/moderate", %{"action" => "lock", "reason" => "Done"})
    assert redirected_to(conn) == ~p"/t/#{topic.id}/#{topic.slug}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Topic locked."
    refute has_element?(lv, "#composer")
    assert has_element?(lv, "#topic-closed")

    html = page(build_conn(), topic)
    assert html =~ ~s(id="topic-locked")
    assert build_conn() |> get(~p"/c/general") |> html_response(200) =~ "Locked"

    post(moderator, ~p"/t/#{topic.id}/moderate", %{"action" => "pin"})
    assert page(build_conn(), topic) =~ ~s(id="topic-pinned")

    # Members cannot, and unknown actions are not found.
    conn = post(member, ~p"/t/#{topic.id}/moderate", %{"action" => "unlock"})
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You cannot moderate this topic."
    assert Forum.get_viewable_topic(nil, topic.id).state == "locked"

    assert_error_sent 404, fn ->
      post(moderator, ~p"/t/#{topic.id}/moderate", %{"action" => "nuke"})
    end
  end
end

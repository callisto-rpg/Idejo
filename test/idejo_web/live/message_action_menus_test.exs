# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MessageActionMenusTest do
  @moduledoc """
  A message's actions (steward request, 2026-11-09): "New Topic", and when the row would
  wrap, "Quote" (Reply, Forward, New Topic) and "Moderate" (the moderators' actions) menus.
  The collapsing itself is the browser's (`assets/js/message_action_menus.js`).
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    ada = user_fixture(%{display_name: "Ada"})
    {:ok, topic} = Forum.create_topic(ada, general, %{"title" => "Plans", "body" => "Ideas?"})
    {:ok, message} = Forum.post_message(ada, topic, %{"body" => "A thought"})
    %{conn: conn, admin: admin, topic: topic, message: message}
  end

  defp watch(conn, user, topic),
    do:
      live_isolated(log_in_user(conn, user), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

  test "Reply, Forward and New Topic are grouped under Quote", %{
    conn: conn,
    topic: topic,
    message: message
  } do
    {:ok, lv, _html} = watch(conn, user_fixture(), topic)
    id = message.id

    assert has_element?(lv, "#message-#{id}-actions[phx-hook=MessageActions]")
    assert has_element?(lv, "#message-#{id}-quote-toggle[aria-expanded=false]", "Quote")
    assert has_element?(lv, "#message-#{id}-quote-items #message-#{id}-reply", "Reply")
    assert has_element?(lv, "#message-#{id}-quote-items #message-#{id}-forward-action")
    assert has_element?(lv, "#message-#{id}-quote-items #message-#{id}-fork", "New Topic")
    refute has_element?(lv, "#message-#{id}-actions", "New topic from this")

    # Report stays in the row; a member gets no Moderate group.
    refute has_element?(lv, "#message-#{id}-quote-items #message-#{id}-report")
    assert has_element?(lv, "#message-#{id}-actions > #message-#{id}-report")
    refute has_element?(lv, "#message-#{id}-moderation")
  end

  test "a moderator's actions are grouped under Moderate", %{
    conn: conn,
    admin: admin,
    topic: topic,
    message: message
  } do
    {:ok, lv, _html} = watch(conn, admin, topic)
    id = message.id

    assert has_element?(lv, "#message-#{id}-moderation-toggle", "Moderate")
    assert has_element?(lv, "#message-#{id}-moderation-items #message-#{id}-moderate")
    assert has_element?(lv, "#message-#{id}-moderation-items #message-#{id}-warn", "Warn user")
  end

  test "the row collapses only with scripts, measured in the browser" do
    js = File.read!("assets/js/message_action_menus.js")
    assert js =~ ~s|row.setAttribute("data-collapsed", "")|
    assert js =~ "new ResizeObserver(schedule)"
    assert js =~ ~s|toggle.setAttribute("aria-expanded", "true")|

    css = File.read!("assets/css/app.css")
    assert css =~ ".message-action-group { display: contents; }"
    assert css =~ ".message-action-group-toggle { display: none; }"
  end
end

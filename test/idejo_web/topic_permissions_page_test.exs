# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicPermissionsPageTest do
  @moduledoc """
  The topic's Permissions page, the `!new-topic` card and "Pin message" (steward request,
  2026-11-13).
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.{Access, Forum}
  alias Idejo.Forum.Topic
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Plans", "body" => "Soon"})

    %{admin: admin, general: general, topic: topic, member: Access.built_in_role!(:member)}
  end

  defp topic_view(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  test "moderators set a topic's permissions on its page; others do not find it", %{
    conn: conn,
    admin: admin,
    topic: topic,
    member: member
  } do
    assert_error_sent 404, fn ->
      conn |> log_in_user(user_fixture()) |> get(~p"/topic-permissions/#{topic.id}")
    end

    conn = log_in_user(conn, admin)
    html = conn |> get(~p"/topic-permissions/#{topic.id}") |> html_response(200)
    assert html =~ ~s(id="topic-permission-#{member.id}-view")
    refute html =~ Access.built_in_role!(:owner).id

    conn =
      post(conn, ~p"/topic-permissions/#{topic.id}", %{
        "permissions" => %{member.id => %{"view" => "deny", "post" => "unset"}}
      })

    assert redirected_to(conn) == ~p"/t/#{topic.id}/#{topic.slug}"
    assert Access.topic_permissions(topic) == %{{member.id, :view} => :deny}
    refute Access.can?(user_fixture(), :view, topic)
  end

  test "!new-topic:Title: opens the card; moderators start a topic with its permissions", %{
    conn: conn,
    admin: admin,
    topic: topic,
    member: member
  } do
    conn = log_in_user(conn, admin)
    {:ok, view, _html} = topic_view(conn, topic)

    render_hook(view, "open_new_topic", %{"title" => "Fresh start"})
    assert has_element?(view, "#new-topic-dialog")
    assert has_element?(view, ~s(#new-topic-title[value="Fresh start"]))
    assert has_element?(view, "#new-topic-permissions")

    view
    |> form("#new-topic-form", new_topic: %{body: ""})
    |> render_submit()

    assert has_element?(view, "#new-topic-body-error")

    assert {:error, {:redirect, %{to: to}}} =
             view
             |> form("#new-topic-form", new_topic: %{body: "First words"})
             |> render_submit(%{"permissions" => %{member.id => %{"post" => "deny"}}})

    new = Repo.get_by!(Topic, title: "Fresh start")
    assert to == "/t/#{new.id}/#{new.slug}"
    assert new.category_id == topic.category_id
    assert Access.topic_permissions(new) == %{{member.id, :post} => :deny}
  end

  test "a member's card has no permissions; Cancel closes it", %{conn: conn, topic: topic} do
    conn = log_in_user(conn, user_fixture())
    {:ok, view, _html} = topic_view(conn, topic)

    render_hook(view, "new_topic", %{})
    assert has_element?(view, "#new-topic-dialog")
    refute has_element?(view, "#new-topic-permissions")

    render_hook(view, "hide_new_topic", %{})
    refute has_element?(view, "#new-topic-dialog")
  end

  test "moderators pin a message to the navigator", %{conn: conn, admin: admin, topic: topic} do
    [opening] = Forum.list_messages(topic)
    conn = log_in_user(conn, admin)
    {:ok, view, _html} = topic_view(conn, topic)

    view |> element("#message-#{opening.id}-pin") |> render_click()
    assert has_element?(view, ~s(#topic-nav-pin-#{opening.id}[href="#message-#{opening.id}"]))
    assert has_element?(view, "#message-#{opening.id}-pin", "Unpin message")

    view |> element("#message-#{opening.id}-pin") |> render_click()
    refute has_element?(view, "#topic-nav-pins")
  end
end

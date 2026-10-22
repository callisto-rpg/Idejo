# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserActionsTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture(%{display_name: "Spammer"})
    {:ok, topic} = Forum.create_topic(member, general, %{"title" => "Plans", "body" => "Hi"})
    %{admin: admin, general: general, member: member, topic: topic}
  end

  defp role_allowed_to_moderate(admin, scope) do
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Mods")})
    {:ok, _} = Access.set_permission(admin, role, scope, :moderate, :allow)
    user = user_fixture()
    {:ok, _} = Access.assign_role(admin, user, role)
    user
  end

  defp card_page(conn, user), do: conn |> get(~p"/u/#{user.id}") |> html_response(200)

  @tag req: "MO-02"
  test "MO-02 everyone who may ban sees “User actions” on the card, and nobody else", %{
    admin: admin,
    general: general,
    member: member
  } do
    may_ban = [
      user_with_role_fixture(:moderator),
      user_with_role_fixture(:owner),
      admin,
      # Any role allowed to moderate server-wide.
      role_allowed_to_moderate(admin, :server)
    ]

    for viewer <- may_ban do
      page = card_page(log_in_user(build_conn(), viewer), member)
      assert page =~ ~s(id="user-actions")
      assert page =~ "User actions"
    end

    may_not = [
      user_fixture(),
      # Moderating one category is not enough to ban.
      role_allowed_to_moderate(admin, general)
    ]

    for viewer <- may_not do
      refute card_page(log_in_user(build_conn(), viewer), member) =~ "user-actions"
    end

    refute card_page(build_conn(), member) =~ "user-actions"
    # Not on one's own card.
    refute card_page(log_in_user(build_conn(), admin), admin) =~ "user-actions"
  end

  @tag req: "MO-02"
  test "MO-02 the actions offer a ban, lifting it, or say why there is none", %{
    admin: admin,
    member: member
  } do
    conn = log_in_user(build_conn(), user_with_role_fixture(:moderator))

    page = card_page(conn, member)
    assert page =~ ~s(id="user-actions-ban")
    assert page =~ ~s(id="ban-form")
    refute page =~ "unban-form"

    {:ok, _} = Accounts.ban_user(admin, member, nil, "Spam")
    page = card_page(conn, member)
    assert page =~ "Banned for good."
    assert page =~ ~s(id="unban-form")
    refute page =~ ~s(id="ban-form")

    page = card_page(conn, admin)
    assert page =~ ~s(id="user-actions")
    assert page =~ "Owners and administrators cannot be banned."
    refute page =~ "ban-form"
  end

  @tag req: "MO-02"
  test "MO-02 in a topic, the card's actions ban and lead back to the topic", %{
    member: member,
    topic: topic
  } do
    moderator = user_with_role_fixture(:moderator)
    conn = log_in_user(build_conn(), moderator)
    topic_path = ~p"/t/#{topic.id}/#{topic.slug}"

    {:ok, reader, _html} =
      live_isolated(log_in_user(build_conn(), user_fixture()), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    render_hook(reader, "show_card", %{"kind" => "user", "ref" => member.id})
    refute has_element?(reader, "#user-actions")

    {:ok, lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    render_hook(lv, "show_card", %{"kind" => "user", "ref" => member.id})
    assert has_element?(lv, "dialog#inline-card #user-actions summary", "User actions")
    assert has_element?(lv, "#ban-form input[name=return_to][value='#{topic_path}']")

    conn = post(conn, ~p"/u/#{member.id}/ban", %{"days" => "1", "return_to" => topic_path})
    assert redirected_to(conn) == topic_path
    assert Accounts.banned?(Accounts.get_user!(member.id))

    # Only a topic's own path is followed back.
    for elsewhere <- ["//evil.example", "https://evil.example/t/x", "/t/../admin", "/admin"] do
      conn =
        delete(log_in_user(build_conn(), moderator), ~p"/u/#{member.id}/ban", %{
          "return_to" => elsewhere
        })

      assert redirected_to(conn) == ~p"/u/#{member.id}"
    end
  end
end

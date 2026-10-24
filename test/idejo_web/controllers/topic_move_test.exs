# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicMoveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff"})
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), staff, :view, :deny)
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), staff, :view, :deny)

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Plans", "body" => "Hi"})

    %{staff: staff, topic: topic}
  end

  @tag req: "TP-15"
  test "TP-15 a moderator moves a topic from its page; viewers who lose it see it go", %{
    staff: staff,
    topic: topic
  } do
    moderator = log_in_user(build_conn(), user_with_role_fixture(:moderator))
    page = moderator |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)
    assert page =~ ~s(id="move-target")

    assert page =~
             ~r/<input[^>]*type="radio"[^>]*name="category_id"[^>]*value="#{staff.id}"[^>]*>\s*<span>Staff<\/span>/

    {:ok, visitor, _html} =
      live_isolated(build_conn(), IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    conn =
      post(moderator, ~p"/t/#{topic.id}/moderate", %{
        "action" => "move",
        "category_id" => staff.id
      })

    assert redirected_to(conn) == ~p"/t/#{topic.id}/#{topic.slug}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Topic moved to Staff."

    assert has_element?(visitor, "#topic-gone")
    refute has_element?(visitor, "#messages li")

    assert redirected_to(get(build_conn(), ~p"/t/#{topic.id}/#{topic.slug}")) ==
             ~p"/users/sign-in"

    assert_error_sent 404, fn ->
      post(moderator, ~p"/t/#{topic.id}/moderate", %{
        "action" => "move",
        "category_id" => Ecto.UUID.generate()
      })
    end
  end
end

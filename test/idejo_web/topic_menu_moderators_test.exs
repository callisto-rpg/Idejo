# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The topic menu's moderation items (steward decision, 2026-11-01): for moderators too, only
# where their :moderate right reaches.
defmodule IdejoWeb.TopicMenuModeratorsTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Reading
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})
    {:ok, garden} = Forum.create_category(admin, %{"name" => "Garden"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Plans", "body" => "Hi"})
    {:ok, help_topic} = Forum.create_topic(starter, help, %{"title" => "Stuck", "body" => "?"})
    moderator = moderator_of(admin, [general, garden])

    %{
      admin: admin,
      general: general,
      help: help,
      garden: garden,
      topic: topic,
      help_topic: help_topic,
      moderator: moderator
    }
  end

  # A user who moderates only `categories`, through a custom role.
  defp moderator_of(admin, categories) do
    {:ok, role} =
      Access.create_role(admin, %{"name" => unique_role_name("Mods")})

    for category <- categories,
        do: {:ok, _} = Access.set_permission(admin, role, category, :moderate, :allow)

    user = user_fixture()
    :ok = Access.grant_role(user, role)
    user
  end

  defp menu(conn) do
    conn
    |> get(~p"/")
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("#topic-menu")
  end

  test "a category moderator gets the items, with only their categories to move to", %{
    conn: conn,
    general: general,
    garden: garden,
    moderator: moderator
  } do
    menu = conn |> log_in_user(moderator) |> menu()
    assert menu |> LazyHTML.query("#topic-menu-admin") |> Enum.count() == 1

    ids = menu |> LazyHTML.query("#topic-menu-move button") |> LazyHTML.attribute("value")
    assert Enum.sort(ids) == Enum.sort([general.id, garden.id])

    # Members who moderate nowhere get none of it.
    member_menu = build_conn() |> log_in_user(user_fixture()) |> menu()
    assert member_menu |> LazyHTML.query("#topic-menu-admin") |> Enum.count() == 0
  end

  test "the menu's details only for topics of categories they moderate", %{
    conn: conn,
    topic: topic,
    help_topic: help_topic,
    moderator: moderator
  } do
    conn = log_in_user(conn, moderator)

    assert %{"following" => 1, "archived" => false} =
             conn |> get(~p"/topic-menu/#{topic.id}") |> json_response(200)

    assert conn |> get(~p"/topic-menu/#{help_topic.id}") |> json_response(404)
  end

  test "they mark topics inactive, move, archive and delete them where they moderate", %{
    conn: conn,
    general: general,
    help: help,
    garden: garden,
    topic: topic,
    help_topic: help_topic,
    moderator: moderator
  } do
    assert {:error, :forbidden} = Forum.mark_inactive(moderator, help_topic)
    {:ok, marked} = Forum.mark_inactive(moderator, topic)
    assert Reading.inactive?(marked)

    conn =
      conn
      |> log_in_user(moderator)
      |> put_req_header("referer", "http://www.example.com/c/#{general.slug}")

    post_menu = fn topic, params ->
      post(conn, ~p"/t/#{topic.id}/moderate", Map.put(params, "return", "back"))
    end

    # Not into a category they do not moderate (404, as from the topic page).
    assert_error_sent 404, fn ->
      post_menu.(topic, %{"action" => "move", "category_id" => help.id})
    end

    assert Repo.get!(Topic, topic.id).category_id == general.id

    res = post_menu.(topic, %{"action" => "move", "category_id" => garden.id})
    assert redirected_to(res) == "/c/#{general.slug}"
    assert Repo.get!(Topic, topic.id).category_id == garden.id

    res = post_menu.(help_topic, %{"action" => "delete", "confirm" => "yes"})
    assert Phoenix.Flash.get(res.assigns.flash, :error) == "You cannot moderate this topic."
    assert Repo.get(Topic, help_topic.id)

    post_menu.(Repo.get!(Topic, topic.id), %{"action" => "delete", "confirm" => "yes"})
    refute Repo.get(Topic, topic.id)
  end
end

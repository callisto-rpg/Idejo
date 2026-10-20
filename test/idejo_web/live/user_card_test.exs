# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserCardTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, team} = Access.create_role(admin, %{"name" => "Team", "colour" => "#336699"})
    ada = user_fixture(%{username: "ada_love", display_name: "Ada"})
    :ok = Access.grant_role(ada, team)

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi @ada_love"})

    %{ada: ada, topic: topic}
  end

  @tag req: "TP-10"
  test "TP-10 a mention leads to the user card at the user's URI, without JavaScript", %{
    ada: ada,
    topic: topic
  } do
    topic_page = build_conn() |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)
    assert topic_page =~ ~s(href="/u/#{ada.id}")

    page = build_conn() |> get(~p"/u/#{ada.id}") |> html_response(200)
    doc = LazyHTML.from_document(page)
    assert doc |> LazyHTML.query("#user-card-name") |> LazyHTML.text() =~ "Ada"
    assert page =~ "@ada_love"
    assert doc |> LazyHTML.query("#user-card-content li") |> LazyHTML.text() =~ "Team"
    assert doc |> LazyHTML.query("#user-card-content li") |> LazyHTML.text() =~ "Member"

    assert_error_sent 404, fn -> get(build_conn(), "/u/not-an-id") end
    assert_error_sent 404, fn -> get(build_conn(), "/u/#{Ecto.UUID.generate()}") end
  end

  @tag req: "TP-10"
  test "TP-10 in a topic, a mention opens the user card in a closeable dialog", %{
    ada: ada,
    topic: topic
  } do
    {:ok, lv, _html} =
      live_isolated(build_conn(), IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    assert has_element?(lv, "#topic-live[phx-hook=Mentions]")
    refute has_element?(lv, "#user-card")

    render_hook(lv, "show_user", %{"id" => ada.id})
    assert has_element?(lv, "dialog#user-card[phx-hook=UserCard][aria-labelledby=user-card-name]")
    assert has_element?(lv, "#user-card-name", "Ada")
    assert has_element?(lv, "#user-card", "@ada_love")
    assert has_element?(lv, "#user-card li", "Team")

    lv |> element("#user-card button", "Close") |> render_click()
    refute has_element?(lv, "#user-card")

    render_hook(lv, "show_user", %{"id" => "nonsense"})
    refute has_element?(lv, "#user-card")
  end
end

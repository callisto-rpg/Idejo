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

    {:ok, team} =
      Access.create_role(admin, %{"name" => unique_role_name("Team"), "colour" => "#336699"})

    ada = user_fixture(%{username: unique_username("ada_love"), display_name: "Ada"})
    :ok = Access.grant_role(ada, team)

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{
        "title" => "Chat",
        "body" => "Hi @#{ada.username}"
      })

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
    assert page =~ "@#{ada.username}"
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

    assert has_element?(lv, "#topic-live[phx-hook=InlineLinks]")
    refute has_element?(lv, "#inline-card")

    render_hook(lv, "show_card", %{"kind" => "user", "ref" => ada.id})

    assert has_element?(
             lv,
             "dialog#inline-card[phx-hook=InlineCard][aria-labelledby=inline-card-name]"
           )

    assert has_element?(lv, "#inline-card-name", "Ada")
    assert has_element?(lv, "#inline-card", "@#{ada.username}")
    assert has_element?(lv, "#inline-card li", "Team")
    assert has_element?(lv, ~s(#inline-card a[href="/u/#{ada.id}"]), "Open profile")

    lv |> element("#inline-card button", "Close") |> render_click()
    refute has_element?(lv, "#inline-card")

    render_hook(lv, "show_card", %{"kind" => "user", "ref" => "nonsense"})
    refute has_element?(lv, "#inline-card")
  end

  @tag req: "TP-10"
  test "TP-10 the name above a message leads to the user's card, like an @mention", %{
    ada: ada,
    topic: topic
  } do
    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "Hello"})

    {:ok, lv, _html} =
      live_isolated(build_conn(), IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    assert has_element?(lv, ~s(a.author-name[href="/u/#{ada.id}"]), "Ada")
    assert File.read!("assets/js/inline_cards.js") =~ "a.author-name[href]"
  end
end

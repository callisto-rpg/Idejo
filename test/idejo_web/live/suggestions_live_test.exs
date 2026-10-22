# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SuggestionsLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    robin = user_fixture(%{username: unique_username("robin"), display_name: "Robin"})
    {:ok, topic} = Forum.create_topic(robin, general, %{"title" => "Woods", "body" => "Hi"})
    me = user_fixture()

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{conn: log_in_user(conn, me), general: general, topic: topic, robin: robin}
  end

  @tag req: "TP-10"
  test "TP-10 the composer offers suggestions in a labelled list box", %{
    conn: conn,
    topic: topic,
    robin: robin
  } do
    {:ok, lv, html} = live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})
    assert html =~ ~s(id="composer-suggestions")
    assert html =~ ~s(role="listbox")

    lv |> element("#composer") |> render_hook("suggest", %{"sign" => "@", "q" => ""})

    assert_reply(lv, %{
      items: [%{insert: username, label: "Robin", detail: "@" <> username}]
    })

    assert username == robin.username

    lv |> element("#composer") |> render_hook("suggest", %{"sign" => "#", "q" => "woo"})
    assert_reply(lv, %{items: [%{insert: "woods", label: "Woods", detail: "#woods · General"}]})

    lv |> element("#composer") |> render_hook("suggest", %{"sign" => "?", "q" => "x"})
    assert_reply(lv, %{items: []})
  end

  @tag req: "TP-10"
  test "TP-10 the new-topic editor offers them too", %{conn: conn, general: general} do
    {:ok, lv, html} = live(conn, ~p"/c/#{general.slug}/new")
    assert html =~ ~s(id="topic_body-suggestions")

    lv |> element("#topic_body-suggest") |> render_hook("suggest", %{"sign" => "/", "q" => "gen"})
    assert_reply(lv, %{items: [%{insert: "general", label: "General", detail: "/general"}]})
  end
end

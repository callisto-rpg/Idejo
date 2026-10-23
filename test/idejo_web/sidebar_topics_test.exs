# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SidebarTopicsTest do
  @moduledoc """
  The sidebar's topics (steward decision, 2026-10-23): the topic on screen highlighted and
  listed even when not followed, with "+" to follow it where followed ones have "×"; long
  names end in "…"; a new message makes a name glow.
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    me = user_fixture()

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Picnic", "body" => "Saturday?"})

    %{general: general, me: me, topic: topic}
  end

  defp sidebar(conn, path) do
    conn
    |> get(path)
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("#sidebar")
  end

  defp topic_item(doc, topic),
    do: LazyHTML.query(doc, ~s(.sidebar-topic[data-topic-id="#{topic.id}"]))

  test "the topic on screen is listed and highlighted, with + to follow it when not followed", %{
    me: me,
    topic: topic
  } do
    conn = log_in_user(build_conn(), me)

    doc = sidebar(conn, ~p"/t/#{topic.id}/#{topic.slug}")
    item = topic_item(doc, topic)

    assert doc
           |> LazyHTML.query(~s(.sidebar-topic.is-current[data-topic-id="#{topic.id}"]))
           |> Enum.count() == 1

    assert item
           |> LazyHTML.query(~s(a.sidebar-topic-link[aria-current="page"][title="Picnic"]))
           |> Enum.count() == 1

    assert item
           |> LazyHTML.query(~s(form.sidebar-follow[action="/t/#{topic.id}/follow"]))
           |> Enum.count() == 1

    assert item |> LazyHTML.query("form.sidebar-unfollow") |> Enum.count() == 0

    assert item |> LazyHTML.query(~s(button[aria-label="Follow Picnic"])) |> Enum.count() == 1

    # Elsewhere it is not listed; followed, it has the ×.
    assert conn |> sidebar(~p"/") |> topic_item(topic) |> Enum.count() == 0

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/t/#{topic.id}/#{topic.slug}")
      |> post(~p"/t/#{topic.id}/follow", %{"return" => "back"})

    assert redirected_to(conn) == "/t/#{topic.id}/#{topic.slug}"
    assert Reading.following?(me, topic)

    item = log_in_user(build_conn(), me) |> sidebar(~p"/") |> topic_item(topic)
    assert item |> LazyHTML.query("form.sidebar-unfollow") |> Enum.count() == 1
    assert item |> LazyHTML.query("form.sidebar-follow") |> Enum.count() == 0
    assert item |> LazyHTML.query("[aria-current]") |> Enum.count() == 0
    refute item |> LazyHTML.to_html() =~ "is-current"
  end

  test "the topic on screen is never folded under more topics", %{
    general: general,
    me: me,
    topic: topic
  } do
    :ok = Reading.follow(me, topic)

    for n <- 1..5 do
      {:ok, other} =
        Forum.create_topic(user_fixture(), general, %{"title" => "Other #{n}", "body" => "Hi"})

      :ok = Reading.follow(me, other)
    end

    {:ok, last} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Last", "body" => "Hi"})

    :ok = Reading.follow(me, last)

    doc = log_in_user(build_conn(), me) |> sidebar(~p"/t/#{last.id}/#{last.slug}")
    assert doc |> LazyHTML.query(".sidebar-more .sidebar-topic.is-current") |> Enum.count() == 0
    assert doc |> LazyHTML.query(".sidebar-topic.is-current") |> LazyHTML.text() =~ "Last"
  end

  test "visitors' sidebars list no topic", %{topic: topic} do
    assert build_conn()
           |> sidebar(~p"/t/#{topic.id}/#{topic.slug}")
           |> topic_item(topic)
           |> Enum.count() == 0
  end

  test "/sidebar lists the topic on screen too, when the user may view it", %{
    me: me,
    topic: topic
  } do
    conn = log_in_user(build_conn(), me)

    doc =
      conn
      |> get(~p"/sidebar?topic=#{topic.id}")
      |> html_response(200)
      |> LazyHTML.from_fragment()

    assert doc |> LazyHTML.query(~s(aside#sidebar[data-topic="#{topic.id}"])) |> Enum.count() == 1
    assert doc |> topic_item(topic) |> LazyHTML.query("form.sidebar-follow") |> Enum.count() == 1

    unknown = Ecto.UUID.generate()

    doc =
      conn |> get(~p"/sidebar?topic=#{unknown}") |> html_response(200) |> LazyHTML.from_fragment()

    assert doc |> LazyHTML.query(".sidebar-topic") |> Enum.count() == 0
  end

  test "a new message in the open topic tells the browser, for the sidebar's glow", %{
    me: me,
    topic: topic
  } do
    {:ok, lv, _html} =
      live_isolated(log_in_user(build_conn(), me), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    {:ok, _} = Forum.post_message(user_fixture(), topic, %{"body" => "Count me in"})
    topic_id = topic.id
    assert_push_event(lv, "topic_activity", %{topic_id: ^topic_id})
  end

  test "the stylesheet: names end in …, the glow is half the burn, the sidebar a little larger" do
    css = File.read!("assets/css/app.css")
    assert css =~ ".sidebar-nav ul { display: grid; grid-template-columns: minmax(0, 1fr);"
    assert css =~ "--sidebar-w: 17rem;"
    assert css =~ "animation: sidebar-burn 2.2s ease-out both;"
    assert css =~ "color: color-mix(in oklab, var(--burn-ink) 50%, currentColor);"
    assert css =~ ".sidebar-topic.is-current {"

    js = File.read!("assets/js/notifier.js")
    assert js =~ ~s(window.addEventListener("phx:topic_activity")
    assert js =~ ~s(url.searchParams.set("topic")
  end
end

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
    [action] = Regex.run(~r/^  \.sidebar-topic-action \{.*?^  \}/ms, css)
    assert action =~ "opacity: 0;"
    assert css =~ ".sidebar-topic.is-current .sidebar-topic-action { opacity: 1; }"

    js = File.read!("assets/js/notifier.js")
    assert js =~ ~s(window.addEventListener("phx:topic_activity")
    assert js =~ ~s(url.searchParams.set("topic")
  end

  # Steward decision, 2026-10-23: categories fold, groups do not.
  test "a category with topics has a fold button; folded, only topics with news show", %{
    general: general,
    me: me,
    topic: topic
  } do
    {:ok, quiet} = Forum.create_topic(me, general, %{"title" => "Quiet", "body" => "Mine"})
    :ok = Reading.follow(me, topic)
    Reading.mark_read(me, topic)
    {:ok, _} = Forum.post_message(user_fixture(), topic, %{"body" => "News"})

    doc = sidebar(log_in_user(build_conn(), me), ~p"/")
    category = LazyHTML.query(doc, ~s(.sidebar-category[data-category-id="#{general.id}"]))

    assert [list_id] =
             category
             |> LazyHTML.query(".sidebar-fold[aria-pressed=false]")
             |> LazyHTML.attribute("aria-controls")

    assert Enum.count(LazyHTML.query(category, "##{list_id}")) == 1
    # What folding keeps: the topic with something new, not the quiet one.
    assert Enum.count(
             LazyHTML.query(doc, ~s(.sidebar-topic.has-news[data-topic-id="#{topic.id}"]))
           ) == 1

    assert Enum.empty?(
             LazyHTML.query(doc, ~s(.sidebar-topic.has-news[data-topic-id="#{quiet.id}"]))
           )

    css = File.read!("assets/css/app.css")
    assert css =~ ".sidebar-category.is-folded {"
    assert css =~ "& .sidebar-topic:not(.has-news, .is-current),"

    js = File.read!("assets/js/sidebar.js")
    assert js =~ ~s(const FOLDED = "idejo:folded-categories")
    assert File.read!("assets/js/notifier.js") =~ "applyFolds()"

    # A category with no topics listed has nothing to fold.
    {:ok, _} = Forum.create_category(user_with_role_fixture(:administrator), %{"name" => "Empty"})
    doc = sidebar(log_in_user(build_conn(), me), ~p"/")
    assert Enum.count(LazyHTML.query(doc, ".sidebar-fold")) == 1
  end

  # Steward decision, 2026-10-25: the × first says "Topic unfollowed", with Cancel, for 4 s.
  @tag req: "TP-13"
  test "TP-13 the sidebar's × waits 4 s with Cancel before a quiet unfollow", %{
    me: me,
    topic: topic
  } do
    :ok = Reading.follow(me, topic)
    conn = log_in_user(build_conn(), me)

    form =
      conn
      |> sidebar(~p"/")
      |> topic_item(topic)
      |> LazyHTML.query(
        ~s(form.sidebar-unfollow[data-unfollowed="Topic unfollowed"][data-cancel="Cancel"])
      )

    assert Enum.count(form) == 1

    # The delayed request, `quiet=1`: unfollowed, and no message waits for the next page.
    conn = delete(conn, ~p"/t/#{topic.id}/follow", %{"return" => "back", "quiet" => "1"})
    refute Reading.following?(me, topic)
    refute Phoenix.Flash.get(conn.assigns.flash, :info)

    # Without it (no JavaScript), the message shows as before.
    :ok = Reading.follow(me, topic)
    conn = delete(build_conn() |> log_in_user(me), ~p"/t/#{topic.id}/follow")
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "no longer follow"

    js = File.read!("assets/js/sidebar.js")
    assert js =~ "const UNDO_MS = 4000"
    assert js =~ ~s|data.set("quiet", "1")|
    assert js =~ ~s|window.addEventListener("pagehide"|

    css = File.read!("assets/css/app.css")
    assert css =~ ~r/\.sidebar-undo-text \{[^}]*color: var\(--color-error\)/

    assert css =~
             ~r/\.sidebar-topic\.is-unfollowing \{\s*& > :not\(\.sidebar-undo\) \{ display: none; \}/
  end

  # Steward decision, 2026-10-25: on phones the drawer fills the screen and the sidebar's
  # tutorial bubbles stay away; topics are a little bigger to tap.
  test "the drawer takes the whole width, without bubbles, and topics are bigger to tap" do
    css = File.read!("assets/css/app.css")

    assert css =~
             ~r/@media \(max-width: 1023\.98px\) \{\s*\.app-sidebar \{\s*position: fixed;\s*left: 0;\s*width: 100%;/

    assert css =~ "padding: 0.5rem 0.5rem 0.5rem 0.375rem"

    js = File.read!("assets/js/sidebar.js")
    assert js =~ "const showBubble = el => {\n  if (!wide.matches) return"
    assert js =~ "if (peeked || !wide.matches ||"
  end
end

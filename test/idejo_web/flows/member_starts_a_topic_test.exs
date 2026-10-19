# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Flows.MemberStartsATopicTest do
  @moduledoc """
  MVP §4, "Member starts a topic": the exit check of M2, with "a public topic renders without
  JavaScript" (MVP §7, §8). It drives the real pages, in order, as a member would: sign in,
  open a category, "New topic", write and preview without anyone seeing it, post; then the
  topic is at the top of the list with its first message closed, and a visitor reads it.
  """
  use IdejoWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Repo

  defp titles(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#topics li > a")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp topic_list(conn), do: conn |> get(~p"/c/general") |> html_response(200) |> titles()

  @tag flow: "member-starts-a-topic"
  test "a member starts a topic", %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, _} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, _} =
      Forum.create_topic(user_fixture(), Forum.get_category_by_slug("general"), %{
        "title" => "Earlier talk",
        "body" => "Already here"
      })

    member = user_fixture(%{display_name: "Mia Member"})
    other_member = log_in_user(build_conn(), user_fixture())

    # The member signs in.
    conn =
      post(conn, ~p"/users/sign-in", %{
        "user" => %{"email" => member.email, "password" => valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/"
    conn = recycle(conn)

    # 1. Opens a category and selects "New topic".
    home = conn |> get(~p"/") |> html_response(200)
    assert home =~ ~s(href="/c/general")

    category = conn |> get(~p"/c/general") |> html_response(200)

    [new_topic_path] =
      category
      |> LazyHTML.from_document()
      |> LazyHTML.query("#new-topic")
      |> LazyHTML.attribute("href")

    assert new_topic_path == "/c/general/new"
    {:ok, lv, _html} = live(conn, new_topic_path)

    # 2. Writes a title and a first message, and previews it; nobody sees it yet.
    lv
    |> form("#new-topic-form",
      topic: %{title: "Picnic on Saturday", body: "Who brings **bread**?"}
    )
    |> render_change()

    lv |> element("#topic_body-preview-tab") |> render_click()
    assert lv |> element("#topic_body-preview") |> render() =~ "<strong>bread</strong>"

    refute Repo.exists?(from t in Topic, where: t.title == "Picnic on Saturday")

    for viewer <- [build_conn(), other_member] do
      refute "Picnic on Saturday" in topic_list(viewer)
    end

    # 3. Posts: the topic page opens, and the topic tops the category list.
    {:ok, topic_conn} =
      lv
      |> form("#new-topic-form",
        topic: %{title: "Picnic on Saturday", body: "Who brings **bread**?"}
      )
      |> render_submit()
      |> follow_redirect(conn)

    topic = Repo.get_by!(Topic, title: "Picnic on Saturday")
    assert topic_conn.request_path == "/t/#{topic.id}/picnic-on-saturday"
    assert html_response(topic_conn, 200) =~ "Mia Member"

    assert topic_list(build_conn()) == ["Picnic on Saturday", "Earlier talk"]
    assert topic_list(other_member) == ["Picnic on Saturday", "Earlier talk"]

    # Its first message is closed: posted together with the title, never open (GM-14).
    assert [first] = Forum.list_messages(topic)
    assert first.state == "closed"
    assert first.closed_at == first.opened_at
    assert first.author_id == member.id

    # A public topic renders without JavaScript: everything is in the HTML a visitor gets,
    # with no LiveView on the page, and it is found through the sitemap at its canonical URL.
    visitor_html =
      build_conn() |> get(~p"/t/#{topic.id}/picnic-on-saturday") |> html_response(200)

    doc = LazyHTML.from_document(visitor_html)

    assert doc |> LazyHTML.query("h1") |> LazyHTML.text() =~ "Picnic on Saturday"
    assert doc |> LazyHTML.query("#message-#{first.id}") |> LazyHTML.text() =~ "Who brings"
    assert visitor_html =~ "<strong>bread</strong>"
    assert LazyHTML.query(doc, "[data-phx-session]") |> Enum.count() == 0

    canonical = IdejoWeb.Endpoint.url() <> "/t/#{topic.id}/picnic-on-saturday"

    assert doc |> LazyHTML.query(~s(link[rel="canonical"])) |> LazyHTML.attribute("href") ==
             [canonical]

    assert build_conn() |> get(~p"/sitemap.xml") |> response(200) =~ "<loc>#{canonical}</loc>"
  end
end

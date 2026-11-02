# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The header's "Server › Category › Topic" (steward decision, 2026-11-02): no requirement ID.
defmodule IdejoWeb.BreadcrumbTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "Garden"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Tomatoes", "body" => "Hi"})

    %{category: general, topic: topic}
  end

  defp page(path),
    do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()

  test "a topic page names its server, category and topic in the header", %{
    category: category,
    topic: topic
  } do
    doc = page(~p"/t/#{topic.id}/#{topic.slug}")
    assert doc |> LazyHTML.query("header #brand .brand-name") |> LazyHTML.text() =~ "Idejo"

    crumbs = LazyHTML.query(doc, "header nav#breadcrumb[aria-label=Breadcrumb]")
    category_link = LazyHTML.query(crumbs, "a#breadcrumb-category")
    assert LazyHTML.text(category_link) =~ "Garden"
    assert LazyHTML.attribute(category_link, "href") == ["/c/#{category.slug}"]
    assert LazyHTML.attribute(category_link, "aria-current") == []

    topic_link = LazyHTML.query(crumbs, "a#breadcrumb-topic")
    assert LazyHTML.text(topic_link) =~ "Tomatoes"
    assert LazyHTML.attribute(topic_link, "aria-current") == ["page"]
    # On phones (steward decision, 2026-11-03) the category shows as its icon: the mark is
    # there, decorative, and the name stays in the link for screen readers.
    assert category_link |> LazyHTML.query(".category-mark[aria-hidden=true]") |> Enum.count() ==
             1

    assert category_link |> LazyHTML.query(".header-crumb-name") |> LazyHTML.text() =~ "Garden"

    assert crumbs |> LazyHTML.query("li.header-crumb.is-last a#breadcrumb-topic") |> Enum.count() ==
             1

    css = File.read!("assets/css/app.css")
    assert css =~ ".header-crumb.is-last[data-cut] {"
    assert css =~ "mask-image: linear-gradient(to right, #000 calc(100% - 1.5rem), transparent);"
    assert File.read!("assets/js/breadcrumb.js") =~ ~s(toggleAttribute("data-cut")
    assert File.read!("assets/js/app.js") =~ ~s(import "./breadcrumb")

    # The separators are not read out.
    assert crumbs |> LazyHTML.query(".header-crumb-sep[aria-hidden=true]") |> Enum.count() == 2
  end

  test "a category page names its category; other pages have no breadcrumb", %{
    category: category
  } do
    doc = page(~p"/c/#{category.slug}")
    link = LazyHTML.query(doc, "header #breadcrumb a#breadcrumb-category")
    assert LazyHTML.text(link) =~ "Garden"
    assert LazyHTML.attribute(link, "aria-current") == ["page"]
    assert doc |> LazyHTML.query("#breadcrumb-topic") |> Enum.count() == 0
    # Its own page: the name, no icon.
    assert link |> LazyHTML.query(".category-mark") |> Enum.count() == 0

    assert ~p"/" |> page() |> LazyHTML.query("#breadcrumb") |> Enum.count() == 0
  end

  test "a private conversation reads Server › Private Conversations › the other person" do
    ada = user_fixture(%{display_name: "Ada"})
    bo = user_fixture(%{display_name: "Bo Builder"})
    {:ok, topic} = Idejo.Conversations.start(ada, bo)
    conn = log_in_user(build_conn(), ada)

    doc = conn |> get(~p"/p/#{topic.id}") |> html_response(200) |> LazyHTML.from_document()
    crumbs = LazyHTML.query(doc, "header nav#breadcrumb[aria-label=Breadcrumb]")

    list = LazyHTML.query(crumbs, "a#breadcrumb-conversations")
    assert LazyHTML.attribute(list, "href") == ["/p"]
    assert LazyHTML.attribute(list, "aria-current") == []
    # On phones, the chat icon; the name stays for screen readers.
    assert list |> LazyHTML.query(".header-crumb-icon") |> Enum.count() == 1

    assert list |> LazyHTML.query(".header-crumb-name") |> LazyHTML.text() =~
             "Private Conversations"

    other = LazyHTML.query(crumbs, "li.header-crumb.is-last a#breadcrumb-conversation")
    assert LazyHTML.text(other) =~ "Bo Builder"
    refute LazyHTML.text(other) =~ "Ada"
    assert LazyHTML.attribute(other, "href") == ["/p/#{topic.id}"]
    assert LazyHTML.attribute(other, "aria-current") == ["page"]

    # The list of conversations: its name, the current page.
    doc = conn |> get(~p"/p") |> html_response(200) |> LazyHTML.from_document()
    list = LazyHTML.query(doc, "#breadcrumb a#breadcrumb-conversations")
    assert LazyHTML.attribute(list, "aria-current") == ["page"]
    assert list |> LazyHTML.query(".header-crumb-icon") |> Enum.count() == 0
    assert doc |> LazyHTML.query("#breadcrumb-conversation") |> Enum.count() == 0
  end
end

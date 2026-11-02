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

    assert ~p"/" |> page() |> LazyHTML.query("#breadcrumb") |> Enum.count() == 0
  end
end

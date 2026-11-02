# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SearchControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(%{display_name: "Ada"}), general, %{
        "title" => "Picnic",
        "body" => "Bring <script>cake</script> please"
      })

    %{topic: topic, help: help}
  end

  @tag req: "SE-01"
  test "SE-01 visitors search without JavaScript, with a category filter", %{
    conn: conn,
    topic: topic
  } do
    [message] = Forum.list_messages(topic)
    # The search box sits in the sidebar, after Filter by tag (steward decision, 2026-11-02).
    home = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    form = LazyHTML.query(home, "#sidebar-quicklinks-more form#sidebar-search[role=search]")
    assert LazyHTML.attribute(form, "action") == ["/search"]
    assert LazyHTML.attribute(form, "method") == ["get"]
    assert form |> LazyHTML.query("input#sidebar-search-q[name=q]") |> Enum.count() == 1
    assert home |> LazyHTML.query("header form[role=search]") |> Enum.count() == 0

    assert home
           |> LazyHTML.query("#sidebar-quicklinks-more > *")
           |> Enum.map(&(LazyHTML.attribute(&1, "id") |> List.first()))
           |> Enum.take(3) == ["tags-link", "sidebar-search", "search-link"]

    page = conn |> get(~p"/search") |> html_response(200)
    assert page =~ ~s(id="search-form")
    refute page =~ "Nothing found."

    page = conn |> get(~p"/search?q=cake") |> html_response(200)
    doc = LazyHTML.from_document(page)

    assert doc
           |> LazyHTML.query(~s(#result-#{message.id} a[href="/m/#{message.id}"]))
           |> LazyHTML.text() =~ "Picnic"

    assert doc |> LazyHTML.query("#result-#{message.id} mark") |> LazyHTML.text() == "cake"
    assert page =~ "Ada"
    # Words written inside something that looks like a tag are found too, and the excerpt is
    # text, never HTML.
    refute page =~ "<script>"

    assert conn |> get(~p"/search?q=cake&category=help") |> html_response(200) =~ "Nothing found."

    assert conn |> get(~p"/search?q=cake&category=general") |> html_response(200) =~
             ~s(id="result-#{message.id}")
  end
end

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
    assert conn |> get(~p"/") |> html_response(200) =~ ~s(id="search-link")

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

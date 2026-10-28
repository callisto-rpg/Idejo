# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# `!spoiler:overlay text:` and `||spoilers||` (steward decision, 2026-10-28): no requirement ID.
defmodule Idejo.SpoilersTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Forum
  alias Idejo.Markdown
  alias Idejo.Messages
  alias Idejo.Uploads

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Books", "body" => "Hi"})
    %{author: author, topic: topic}
  end

  test "||text|| renders as a spoiler, never from raw HTML or inside code" do
    assert Markdown.to_html("a ||b **c**|| d") ==
             ~s(<p>a <span class="spoiler">b <strong>c</strong></span> d</p>)

    refute Markdown.to_html("`||b||`") =~ "spoiler\">"
    refute Markdown.to_html(~s(<span class="spoiler">x</span>)) =~ "<span"
    assert Markdown.to_html("x || y || z") == "<p>x || y || z</p>"
  end

  test "the cover's words: trimmed, at most 100 characters, gone with the spoiler", %{
    author: author,
    topic: topic
  } do
    {:ok, message} = Forum.post_message(author, topic, %{"body" => "The end"})

    assert {:ok, %{spoiler_label: "Book 3"}} =
             Messages.set_spoiler(author, message, true, "  Book 3 ")

    {:ok, message} = Messages.set_spoiler(author, message, true, String.duplicate("a", 150))
    assert String.length(message.spoiler_label) == 100
    assert {:ok, %{spoiler_label: nil}} = Messages.set_spoiler(author, message, true, " ")
    {:ok, message} = Messages.set_spoiler(author, message, true, "Book 3")

    assert {:ok, %{spoiler: false, spoiler_label: nil}} =
             Messages.set_spoiler(author, message, false, "ignored")
  end

  test "quotes, previews and search never show a ||spoiler||", %{author: author, topic: topic} do
    {:ok, hidden} = Uploads.store_image(author, image_file(:png))
    {:ok, shown} = Uploads.store_image(author, image_file(:png))

    body =
      "Xylophone ||a secret ||nested|| word ![x](#{Uploads.url(hidden)})|| " <>
        "then ![y](#{Uploads.url(shown)})"

    {:ok, message} = Forum.post_message(author, topic, %{"body" => body})

    assert Forum.excerpt(message) == "Xylophone (spoiler) then y"

    assert Forum.excerpt_segments(message) == [
             text: "Xylophone (spoiler) then ",
             image: Uploads.url(shown)
           ]

    # Topic cards' pictures.
    %{images: images} = Forum.topic_previews([topic.id])[topic.id]
    assert images == [Uploads.url(shown)]

    {results, _} = Idejo.Search.search(nil, "secret")
    assert [%{excerpt: [text: excerpt]}] = Enum.filter(results, &(&1.message.id == message.id))
    refute excerpt =~ "secret"
  end
end

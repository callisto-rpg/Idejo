# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Compact and expanded topic cards (steward decision, 2026-10-23): no requirement ID.
defmodule IdejoWeb.TopicViewTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture(%{display_name: "Ada"})

    {:ok, topic} =
      Forum.create_topic(starter, general, %{
        "title" => "Garden plans",
        "body" => "Tomatoes along the wall ![](/uploads/garden.webp)"
      })

    %{admin: admin, starter: starter, topic: topic}
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp query(doc, selector), do: LazyHTML.query(doc, selector)
  defp texts(doc, selector), do: doc |> query(selector) |> Enum.map(&LazyHTML.text/1)

  test "compact by default: the toggle, and cards with their tags but no preview", %{} do
    for path <- [~p"/", ~p"/c/general"] do
      doc = doc(build_conn(), path)

      assert ["/" <> _] =
               doc |> query("#view-compact[aria-current=true]") |> LazyHTML.attribute("href")

      assert Enum.count(query(doc, "#view-expanded:not([aria-current])")) == 1
      assert Enum.empty?(query(doc, ".topic-preview"))
    end

    # On the category page, beside its title; on the home page, beside the first section's.
    assert Enum.count(
             query(doc(build_conn(), ~p"/c/general"), "header.category-intro #view-toggle")
           ) == 1

    assert Enum.count(query(doc(build_conn(), ~p"/"), "section.has-view-toggle > #view-toggle")) ==
             1
  end

  test "expanded: the opening text and image, the three latest messages, who wrote there", %{
    admin: admin,
    starter: starter,
    topic: topic
  } do
    writers = for n <- 1..7, do: user_fixture(%{display_name: "Writer #{n}"})

    for {user, n} <- Enum.with_index(writers, 1),
        do: Forum.post_message(user, topic, %{"body" => "Note #{n}"})

    {:ok, spam} = Forum.post_message(starter, topic, %{"body" => "Spam"})
    {:ok, _} = Messages.delete_as_moderator(admin, spam, "Spam")

    conn = get(build_conn(), ~p"/c/general?view=expanded")
    doc = conn |> html_response(200) |> LazyHTML.from_document()
    card = "#topic-#{topic.id}.is-expanded"

    assert texts(doc, "#{card} .topic-preview-text") == ["Tomatoes along the wall"]

    assert doc |> query("#{card} .topic-preview-image") |> LazyHTML.attribute("src") == [
             "/uploads/garden.webp"
           ]

    assert texts(doc, "#{card} .topic-preview-heading") == ["Latest messages"]
    # The three latest, oldest first; the deleted one is left out.
    assert doc |> texts("#{card} .topic-preview-message-text") |> Enum.map(&String.trim/1) ==
             ["Note 5", "Note 6", "Note 7"]

    # Eight wrote there (Ada and seven): five avatars and "+3 more".
    assert Enum.count(query(doc, "#{card} .topic-preview-person")) == 5
    assert texts(doc, "#{card} .topic-preview-more") |> Enum.map(&String.trim/1) == ["+3 more"]
    assert Enum.count(query(doc, "#view-expanded[aria-current=true]")) == 1

    # Remembered for the next pages, the home page too, until Compact is chosen.
    home = conn |> recycle() |> get(~p"/") |> html_response(200)
    assert home =~ "topic-preview"
    compact = conn |> recycle() |> get(~p"/?view=compact")
    refute html_response(compact, 200) =~ "topic-preview"
    refute compact |> recycle() |> get(~p"/c/general") |> html_response(200) =~ "topic-preview"
  end

  test "six writers show in full; a spoiler gives away neither text nor image", %{
    starter: starter,
    topic: topic
  } do
    for n <- 1..5, do: Forum.post_message(user_fixture(), topic, %{"body" => "Hi #{n}"})
    [first | _] = Forum.list_messages(topic)
    {:ok, _} = Messages.set_spoiler(starter, first, true)

    doc = doc(build_conn(), ~p"/c/general?view=expanded")
    assert Enum.count(query(doc, ".topic-preview-person")) == 6
    assert Enum.empty?(query(doc, ".topic-preview-more"))
    assert texts(doc, ".topic-preview-text") == ["(spoiler)"]
    assert Enum.empty?(query(doc, ".topic-preview-image"))
  end

  test "a topic with only its opening message shows no Latest messages", %{topic: topic} do
    preview = Forum.topic_previews([topic.id])[topic.id]
    assert preview.latest == []
    assert preview.participant_count == 1
    doc = doc(build_conn(), ~p"/c/general?view=expanded")
    assert Enum.empty?(query(doc, ".topic-preview-latest"))
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Unarchive a topic (steward decision, 2026-11-01): back, open, to the category it was
# archived from, or to one picked when it has none; in "Moderate this topic" and the
# administrators' topic menu. No requirement ID.
defmodule IdejoWeb.TopicUnarchiveTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Moderation
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, other} = Forum.create_category(admin, %{"name" => "Other"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Plans", "body" => "Hi"})
    {:ok, archived} = Forum.archive_topic(admin, topic)
    %{admin: admin, general: general, other: other, starter: starter, topic: archived}
  end

  defp page(conn, topic), do: conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)

  test "an archived topic goes back, open, to the category it was archived from, logged", %{
    admin: admin,
    general: general,
    other: other,
    starter: starter,
    topic: topic
  } do
    assert Forum.unarchive_target(topic).id == general.id

    assert {:error, :forbidden} = Forum.unarchive_topic(starter, topic, general)
    {:ok, archive} = Forum.archive_category(admin)
    assert {:error, :invalid_target} = Forum.unarchive_topic(admin, topic, archive)

    {:ok, open} = Forum.unarchive_topic(admin, topic, general, "Wrong one")
    assert open.state == "open"
    assert open.category_id == general.id
    assert Forum.can_post?(starter, open)

    {[entry | _], _} = Moderation.list(admin)
    assert entry.action == "topic.unarchive"
    assert entry.category_id == general.id
    assert entry.reason == "Wrong one"
    assert entry.details["to"]["id"] == general.id
    assert IdejoWeb.ModerationHTML.action_label("topic.unarchive") == "Unarchived a topic"

    assert {:error, :not_archived} = Forum.unarchive_topic(admin, open, other)
    assert Forum.unarchive_target(open) == nil
  end

  test "Moderate this topic offers Unarchive to its category, in place of Move", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic
  } do
    conn = log_in_user(conn, admin)
    html = page(conn, topic)
    assert html =~ ~s(id="unarchive-topic")
    assert html =~ "Unarchive to General"
    refute html =~ ~s(id="unarchive-target")
    refute html =~ ~s(id="move-target")

    res = post(conn, ~p"/t/#{topic.id}/moderate", %{"action" => "unarchive"})
    assert Phoenix.Flash.get(res.assigns.flash, :info) == "Topic unarchived to General."
    assert redirected_to(res) == ~p"/t/#{topic.id}/#{topic.slug}"
    assert %{state: "open", category_id: category_id} = Repo.get!(Topic, topic.id)
    assert category_id == general.id

    # Open again: Move is back, Unarchive gone.
    html = page(conn, Repo.get!(Topic, topic.id))
    refute html =~ ~s(id="unarchive-topic")
    assert html =~ ~s(id="move-target")
  end

  test "without the category it came from, the moderator picks one", %{
    conn: conn,
    admin: admin,
    general: general,
    other: other,
    topic: topic
  } do
    {:ok, _} = Forum.delete_category(admin, general, topics: {:move, other})
    assert Forum.unarchive_target(topic) == nil

    conn = log_in_user(conn, admin)
    assert page(conn, topic) =~ ~s(id="unarchive-target")

    res = post(conn, ~p"/t/#{topic.id}/moderate", %{"action" => "unarchive"})

    assert Phoenix.Flash.get(res.assigns.flash, :error) ==
             "Choose the category the topic goes back to."

    assert Repo.get!(Topic, topic.id).state == "archived"

    res =
      post(conn, ~p"/t/#{topic.id}/moderate", %{
        "action" => "unarchive",
        "category_id" => other.id
      })

    assert Phoenix.Flash.get(res.assigns.flash, :info) == "Topic unarchived to Other."
    assert %{state: "open", category_id: category_id} = Repo.get!(Topic, topic.id)
    assert category_id == other.id
  end

  test "the topic menu tells administrators where an archived topic goes back to", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic
  } do
    conn = log_in_user(conn, admin)

    assert %{"archived" => true, "unarchive_to" => %{"id" => id, "name" => "General"}} =
             conn |> get(~p"/topic-menu/#{topic.id}") |> json_response(200)

    assert id == general.id

    menu =
      conn
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#topic-menu")

    # topic_menu.js writes "Unarchive to {category}" into the label, not the icon.
    unarchive = LazyHTML.query(menu, "#topic-menu-unarchive button")
    assert unarchive |> LazyHTML.query(".topic-menu-label") |> Enum.count() == 1
    assert LazyHTML.attribute(unarchive, "data-label") == ["Unarchive to %{category}"]
    assert menu |> LazyHTML.query("#topic-menu-unarchive-toggle") |> Enum.count() == 1

    # From the menu, back to the page it was opened on.
    res =
      conn
      |> put_req_header("referer", "http://www.example.com/c/#{general.slug}")
      |> post(~p"/t/#{topic.id}/moderate", %{"action" => "unarchive", "return" => "back"})

    assert redirected_to(res) == "/c/#{general.slug}"
    assert Repo.get!(Topic, topic.id).state == "open"
  end
end

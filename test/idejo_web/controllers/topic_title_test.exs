# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Changing a topic's title (steward decision, 2026-10-23): no requirement ID.
defmodule IdejoWeb.TopicTitleTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Moderation
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Plans", "body" => "Hi"})

    %{admin: admin, starter: starter, topic: topic}
  end

  defp page(conn, topic), do: conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)

  test "the pencil and its form show to the starter and moderators only", %{
    starter: starter,
    topic: topic
  } do
    for user <- [starter, user_with_role_fixture(:moderator)] do
      html = page(log_in_user(build_conn(), user), topic)
      assert html =~ ~s(id="rename-topic-link")
      assert html =~ ~s(href="#rename-topic")
      assert html =~ ~s(id="rename-topic-title")
    end

    refute page(log_in_user(build_conn(), user_fixture()), topic) =~ "rename-topic"
    refute page(build_conn(), topic) =~ "rename-topic"
  end

  test "the starter renames their topic without JavaScript; the old address redirects", %{
    starter: starter,
    topic: topic
  } do
    Idejo.Messages.subscribe(topic.id)

    conn =
      post(log_in_user(build_conn(), starter), ~p"/t/#{topic.id}/title", %{
        "title" => " Garden plans "
      })

    renamed = Repo.get!(Topic, topic.id)
    assert renamed.title == "Garden plans"
    assert renamed.slug == "garden-plans"
    assert redirected_to(conn) == ~p"/t/#{topic.id}/garden-plans"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Title saved."
    topic_id = topic.id
    assert_receive {:topic_changed, ^topic_id}

    assert build_conn() |> get(~p"/t/#{topic.id}/plans") |> redirected_to(301) ==
             ~p"/t/#{topic.id}/garden-plans"

    # Their own topic: nothing for the moderation log.
    assert {[], _} = Moderation.list(user_with_role_fixture(:administrator))
  end

  test "a moderator's rename of someone else's topic is logged", %{topic: topic} do
    moderator = user_with_role_fixture(:moderator)
    assert {:ok, _} = Forum.rename_topic(moderator, topic, "Plans for spring", "Clearer")

    assert {[entry], _} = Moderation.list(moderator)
    assert entry.action == "topic.rename"
    assert entry.details == %{"from" => "Plans", "to" => "Plans for spring"}
    assert IdejoWeb.ModerationHTML.action_label(entry.action) == "Renamed a topic"
  end

  test "others, blank or long titles, locked topics for the starter and archived ones are refused",
       %{admin: admin, starter: starter, topic: topic} do
    assert {:error, :forbidden} = Forum.rename_topic(user_fixture(), topic, "Mine now")

    conn =
      post(log_in_user(build_conn(), user_fixture()), ~p"/t/#{topic.id}/title", %{"title" => "X"})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "You cannot change the title of this topic."

    assert {:error, %Ecto.Changeset{}} = Forum.rename_topic(starter, topic, "  ")

    assert {:error, %Ecto.Changeset{}} =
             Forum.rename_topic(starter, topic, String.duplicate("a", 151))

    {:ok, locked} = Forum.moderate_topic(admin, topic, :lock)
    assert {:error, :forbidden} = Forum.rename_topic(starter, locked, "Still mine")
    assert {:ok, %{title: "Closed plans"}} = Forum.rename_topic(admin, locked, "Closed plans")

    Repo.update_all(Topic, set: [state: "archived"])
    archived = Repo.get!(Topic, topic.id)
    assert {:error, :forbidden} = Forum.rename_topic(admin, archived, "Old plans")
  end
end

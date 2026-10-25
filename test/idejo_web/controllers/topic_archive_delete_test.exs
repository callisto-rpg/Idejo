# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Archive topic and Permanently delete topic in "Moderate this topic" (steward decision,
# 2026-10-23): no requirement ID.
defmodule IdejoWeb.TopicArchiveDeleteTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages
  alias Idejo.Messages.Message
  alias Idejo.Moderation
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Plans", "body" => "Hi"})
    %{admin: admin, general: general, starter: starter, topic: topic}
  end

  defp page(conn, topic), do: conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)

  test "both show in Moderate this topic, for moderators only", %{starter: starter, topic: topic} do
    html = page(log_in_user(build_conn(), user_with_role_fixture(:moderator)), topic)
    assert html =~ ~s(id="archive-topic")
    assert html =~ ~s(id="delete-topic-form")
    assert html =~ ~r/<input[^>]*name="confirm"[^>]*required/

    refute page(log_in_user(build_conn(), starter), topic) =~ "delete-topic"
  end

  test "archiving moves it, read only, to the Archive, closes open messages, and is logged", %{
    admin: admin,
    starter: starter,
    topic: topic
  } do
    {:ok, open} = Messages.commit(user_fixture(), topic, "Still typing")
    moderator = user_with_role_fixture(:moderator)
    conn = log_in_user(build_conn(), moderator)

    res = post(conn, ~p"/t/#{topic.id}/moderate", %{"action" => "archive", "reason" => "Old"})
    assert Phoenix.Flash.get(res.assigns.flash, :info) == "Topic archived: it is read only now."

    archived = Repo.get!(Topic, topic.id) |> Repo.preload(:category)
    assert archived.state == "archived"
    assert archived.category.archive
    assert Repo.get!(Message, open.id).state == "closed"
    refute Forum.can_post?(starter, archived)
    # The Archive is hidden from moderators: back home.
    assert redirected_to(res) == "/"

    {[entry | _], _} = Moderation.list(admin)
    assert entry.action == "topic.archive"
    assert entry.reason == "Old"
    assert IdejoWeb.ModerationHTML.action_label("topic.archive") == "Archived a topic"

    assert {:error, :archived} = Forum.archive_topic(admin, archived)
    assert {:error, :forbidden} = Forum.archive_topic(starter, topic)
  end

  test "deleting for good needs the box ticked, then removes everything, logged", %{
    admin: admin,
    general: general,
    starter: starter,
    topic: topic
  } do
    {:ok, reply} = Forum.post_message(user_fixture(), topic, %{"body" => "Me too"})
    {:ok, _} = Idejo.Reactions.toggle(starter, reply, "joy")
    {:ok, _} = Moderation.report_message(starter, reply, %{"reason" => "Rude"})
    {:ok, open} = Messages.commit(starter, topic, "Typing")
    # A topic started from its reply stays, without the link.
    {:ok, fork} =
      Forum.create_topic(starter, general, %{"title" => "Side", "body" => "x"},
        forked_from: reply
      )

    conn = log_in_user(build_conn(), user_with_role_fixture(:moderator))

    res = post(conn, ~p"/t/#{topic.id}/moderate", %{"action" => "delete"})
    assert Phoenix.Flash.get(res.assigns.flash, :error) =~ "Tick the box"
    assert Repo.get(Topic, topic.id)

    res =
      post(conn, ~p"/t/#{topic.id}/moderate", %{
        "action" => "delete",
        "confirm" => "yes",
        "reason" => "Spam"
      })

    assert redirected_to(res) == "/c/general"
    assert Phoenix.Flash.get(res.assigns.flash, :info) == "Topic deleted for good."

    refute Repo.get(Topic, topic.id)
    refute Repo.get(Message, reply.id)
    refute Messages.OpenMessage.running?(open.id)
    assert Repo.get!(Topic, fork.id).forked_from_message_id == nil

    assert redirected_to(get(build_conn(), ~p"/t/#{topic.id}/#{topic.slug}")) ==
             ~p"/users/sign-in"

    {[entry | _], _} = Moderation.list(admin)
    assert entry.action == "topic.delete"
    assert entry.details["title"] == "Plans"
    assert IdejoWeb.ModerationHTML.action_label("topic.delete") == "Deleted a topic for good"

    assert {:error, :forbidden} = Forum.delete_topic(starter, fork)
  end
end

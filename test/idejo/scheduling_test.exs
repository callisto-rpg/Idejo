# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# `!schedule` (steward decision, 2026-10-23): no requirement ID.
defmodule Idejo.SchedulingTest do
  use Idejo.DataCase, async: true
  use Oban.Testing, repo: Idejo.Repo

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.{Message, ScheduledMessage, ScheduledWorker, Scheduling}

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()

    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Later", "body" => "Hi"})
    [first] = Forum.list_messages(topic)

    %{admin: admin, author: author, topic: topic, first: first}
  end

  test "hours with decimals, more than 0 and at most 168, at least a minute" do
    assert Scheduling.parse_hours("1.5") == {:ok, 5400}
    assert Scheduling.parse_hours(" 0,25 ") == {:ok, 900}
    assert Scheduling.parse_hours("168") == {:ok, 168 * 3600}
    assert Scheduling.parse_hours("0.001") == {:ok, 60}

    for refused <- ["0", "-1", "168.01", "two", "", "1h"],
        do: assert(Scheduling.parse_hours(refused) == :error, refused)
  end

  test "a scheduled message waits, seen by its author only, then posts closed and marked", %{
    author: author,
    topic: topic,
    first: first
  } do
    Messages.subscribe(topic.id)

    {:ok, scheduled} =
      Scheduling.schedule(author, topic, "See you **soon**", 5400, reply_to_id: first.id)

    assert_receive {:scheduled, author_id} when author_id == author.id
    assert_enqueued(worker: ScheduledWorker, args: %{id: scheduled.id})
    [job] = all_enqueued(worker: ScheduledWorker)
    assert_in_delta DateTime.diff(job.scheduled_at, DateTime.utc_now()), 5400, 5

    assert [%{id: id}] = Scheduling.list_pending(author, topic)
    assert id == scheduled.id
    assert Scheduling.list_pending(user_fixture(), topic) == []
    assert Scheduling.list_pending(nil, topic) == []
    # Nothing is posted yet.
    assert length(Forum.list_messages(topic)) == 1

    assert perform_job(ScheduledWorker, %{id: scheduled.id}) == :ok

    assert [_, %Message{} = posted] = Forum.list_messages(topic)
    assert posted.scheduled
    assert posted.state == "closed"
    assert posted.body_md == "See you **soon**"
    assert posted.reply_to_id == first.id
    assert Scheduling.list_pending(author, topic) == []
    assert_receive {:message, %Message{scheduled: true}}
  end

  test "only its author cancels it, and a cancelled one is never posted", %{
    author: author,
    topic: topic
  } do
    {:ok, scheduled} = Scheduling.schedule(author, topic, "Never mind", 3600)

    assert Scheduling.cancel(user_fixture(), scheduled.id) == {:error, :not_found}
    assert Scheduling.cancel(author, "not-an-id") == {:error, :not_found}
    assert Scheduling.cancel(author, scheduled.id) == :ok
    assert Repo.get(ScheduledMessage, scheduled.id) == nil

    assert perform_job(ScheduledWorker, %{id: scheduled.id}) == :ok
    assert length(Forum.list_messages(topic)) == 1
  end

  test "it needs the post right and text, and is dropped when it may no longer be posted", %{
    admin: admin,
    author: author,
    topic: topic
  } do
    assert Scheduling.schedule(author, topic, "  ", 3600) == {:error, :blank}

    assert Scheduling.schedule(unconfirmed_user_fixture(), topic, "Hi", 3600) ==
             {:error, :forbidden}

    {:ok, scheduled} = Scheduling.schedule(author, topic, "Too late", 3600)
    {:ok, _} = Forum.moderate_topic(admin, topic, :lock)

    assert perform_job(ScheduledWorker, %{id: scheduled.id}) == :ok
    assert length(Forum.list_messages(topic)) == 1
    assert Repo.get(ScheduledMessage, scheduled.id) == nil
  end
end

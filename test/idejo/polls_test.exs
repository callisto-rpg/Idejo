# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# `!poll` and `!spoiler` (steward decisions, 2026-10-23): no requirement ID.
defmodule Idejo.PollsTest do
  use Idejo.DataCase, async: true
  use Oban.Testing, repo: Idejo.Repo

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.{Poll, Polls, PollWorker}

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()

    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Votes", "body" => "Hi"})
    {:ok, message} = Messages.commit(author, topic, "Which day")

    %{admin: admin, author: author, topic: topic, message: message}
  end

  defp poll(author, message, attrs \\ %{}) do
    Polls.create(
      author,
      message,
      Map.merge(
        %{"question" => "Day?", "options" => ["Saturday", " ", "Sunday"], "hours" => "48"},
        attrs
      )
    )
  end

  test "a poll goes under the author's own message, one per message, closing in its hours", %{
    author: author,
    topic: topic,
    message: message
  } do
    Messages.subscribe(topic.id)
    assert {:error, :forbidden} = poll(user_fixture(), message)
    assert {:error, :question} = poll(author, message, %{"question" => " "})
    assert {:error, :options} = poll(author, message, %{"options" => ["Only one"]})
    assert {:error, :options} = poll(author, message, %{"options" => Enum.map(1..11, &"#{&1}")})
    assert {:error, :hours} = poll(author, message, %{"hours" => "169"})
    assert {:error, :hours} = poll(author, message, %{"hours" => nil})

    assert {:ok, summary} = poll(author, message)
    assert summary.question == "Day?"
    assert Enum.map(summary.options, & &1.text) == ["Saturday", "Sunday"]
    refute summary.multiple
    assert_in_delta DateTime.diff(summary.closes_at, DateTime.utc_now()), 48 * 3600, 5
    message_id = message.id
    assert_receive {:poll, ^message_id, ^summary}
    assert_enqueued(worker: PollWorker, args: %{id: summary.id}, scheduled_at: summary.closes_at)

    assert {:error, :taken} = poll(author, message)
  end

  test "posters vote once, or for several answers, and change their vote; counts only", %{
    author: author,
    message: message
  } do
    {:ok, %{options: [sat, sun]}} = poll(author, message, %{"multiple" => "true"})
    voter = user_fixture()

    assert {:ok, summary} = Polls.vote(voter, message, [sat.id, sun.id])
    assert summary.voters == 1
    assert Enum.map(summary.options, & &1.count) == [1, 1]

    assert {:ok, summary} = Polls.vote(voter, message, [sun.id])
    assert Enum.map(summary.options, & &1.count) == [0, 1]

    # Taking the vote back.
    assert {:ok, %{voters: 0}} = Polls.vote(voter, message, [])
    assert {:error, :invalid} = Polls.vote(voter, message, [Ecto.UUID.generate()])
  end

  test "a poll taking one answer refuses several", %{author: author, message: message} do
    {:ok, %{options: [sat, sun]}} = poll(author, message)
    assert {:error, :invalid} = Polls.vote(user_fixture(), message, [sat.id, sun.id])
    assert {:ok, _} = Polls.vote(user_fixture(), message, [sat.id])
  end

  test "who sees the counts: voters, the author, and everyone once it closed", %{
    author: author,
    message: message
  } do
    {:ok, %{options: [sat, _]}} = poll(author, message)
    voter = user_fixture()
    reader = user_fixture()
    {:ok, summary} = Polls.vote(voter, message, [sat.id])

    assert Polls.results_shown?(summary, voter, message)
    assert Polls.results_shown?(summary, author, message)
    refute Polls.results_shown?(summary, reader, message)
    refute Polls.results_shown?(summary, nil, message)
    assert Polls.results_shown?(summary, nil, message, DateTime.add(summary.closes_at, 1))
  end

  test "no votes once it closed, without the post right, or on a deleted message", %{
    admin: admin,
    author: author,
    topic: topic,
    message: message
  } do
    {:ok, %{options: [sat, _]}} = poll(author, message)

    unverified = unconfirmed_user_fixture()
    assert {:error, :forbidden} = Polls.vote(unverified, message, [sat.id])

    {:ok, _} = Forum.moderate_topic(admin, topic, :lock, "Done")
    assert {:error, :forbidden} = Polls.vote(user_fixture(), message, [sat.id])
    {:ok, _} = Forum.moderate_topic(admin, Repo.reload!(topic), :unlock, "Open")

    Repo.update_all(Poll, set: [closes_at: DateTime.add(DateTime.utc_now(), -1)])
    assert {:error, :closed} = Polls.vote(user_fixture(), message, [sat.id])

    {:ok, _} = Messages.delete_as_moderator(admin, Repo.reload!(message), "Spam")
    assert {:error, :forbidden} = Polls.vote(user_fixture(), Repo.reload!(message), [sat.id])
  end

  test "!spoiler marks the author's message only, and quotes and search hide its words", %{
    author: author,
    topic: topic,
    message: message
  } do
    assert {:error, :forbidden} = Messages.set_spoiler(user_fixture(), message, true)
    assert {:ok, %{spoiler: true} = message} = Messages.set_spoiler(author, message, true)
    assert Forum.excerpt(message) == "(spoiler)"

    {results, _more?} = Idejo.Search.search(nil, "which")

    assert [%{excerpt: [text: "(spoiler)"]}] =
             Enum.filter(results, &(&1.message.id == message.id))

    assert {:ok, %{spoiler: false}} = Messages.set_spoiler(author, message, false)
    assert topic.id == message.topic_id
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.MessagesEngineTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.{Message, OpenMessage, Recovery}

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Chat", "body" => "Hi all"})
    author = user_fixture()
    Messages.subscribe(topic.id)

    on_exit(fn -> stop_timers() end)
    %{admin: admin, general: general, topic: topic, author: author}
  end

  defp stop_timers do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
        do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
  end

  defp commit!(author, topic, text, opts \\ []) do
    {:ok, message} = Messages.commit(author, topic, text, opts)
    message
  end

  # Moves the window's end into the past, as if its 15 s had gone by.
  defp end_window!(message) do
    message
    |> Ecto.Changeset.change(closes_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update!()
  end

  @tag req: "GM-01"
  test "GM-01 Enter with no open message posts a new message, open and visible at once", %{
    topic: topic,
    author: author
  } do
    message = commit!(author, topic, "Hello")

    assert message.state == "open"
    assert message.body_md == "Hello."
    assert message.body_html =~ "Hello."
    assert message.uri =~ "/m/#{message.id}"
    assert_receive {:message, %Message{id: id, state: "open"}}
    assert id == message.id

    assert Enum.map(Forum.list_messages(topic), & &1.id) |> List.last() == message.id
    assert Repo.reload!(topic).message_count == 2

    assert [%Activity{verb: "create"}] =
             Repo.all(from a in Activity, where: a.object_uri == ^message.uri)
  end

  @tag req: "GM-02"
  test "GM-02 Enter with an open message commits to it in place", %{topic: topic, author: author} do
    first = commit!(author, topic, "Hello")
    second = commit!(author, topic, "Hello. How are you")

    assert second.id == first.id
    assert second.body_md == "Hello. How are you."
    assert second.state == "open"
    refute second.edited
    assert Repo.aggregate(from(m in Message, where: m.author_id == ^author.id), :count) == 1
    assert Messages.list_versions(second) == []
  end

  @tag req: "GM-02"
  test "GM-02 a dot is added after text that ends without punctuation, not after code", %{
    topic: topic,
    author: author
  } do
    for {sent, stored} <- [
          {"Hello", "Hello."},
          {"Really?", "Really?"},
          {"Wow!  ", "Wow!"},
          {"(see above)", "(see above)"},
          {"Ça va «bien»", "Ça va «bien»"},
          {"```\nx = 1\n```", "```\nx = 1\n```"},
          {"```\nstill typing", "```\nstill typing"},
          {"Look:\n\n    indented", "Look:\n\n    indented"}
        ] do
      message = commit!(author, topic, sent)
      assert message.body_md == stored, "#{inspect(sent)} gave #{inspect(message.body_md)}"
      {:ok, _} = Messages.close(message)
    end
  end

  # Steward decision, 2026-10-26: an author who turned "Automatic punctuation" off gets the
  # text as typed; others keep their dot.
  @tag req: "GM-02"
  test "GM-02 with the author's automatic punctuation off, no dot is added", %{
    topic: topic,
    author: author
  } do
    {:ok, author} = Idejo.Accounts.update_user_writing(author, %{"auto_punctuation" => "false"})

    first = commit!(author, topic, "Hello  ")
    assert first.body_md == "Hello"

    later = commit!(author, topic, "Hello there")
    assert later.id == first.id
    assert later.body_md == "Hello there"

    assert commit!(user_fixture(), topic, "Hi").body_md == "Hi."
  end

  @tag req: "GM-03"
  test "GM-03 the window is fixed at the first commit and appends never move it", %{
    topic: topic,
    author: author
  } do
    first = commit!(author, topic, "One")
    assert DateTime.diff(first.closes_at, first.opened_at) == 15

    later = commit!(author, topic, "One. Two")
    assert later.closes_at == first.closes_at
    assert later.opened_at == first.opened_at
    assert OpenMessage.running?(first.id)
  end

  @tag req: "GM-03"
  test "GM-03 when the window ends the timer says so, and the message stays open", %{
    topic: topic,
    author: author
  } do
    message = commit!(author, topic, "One")
    OpenMessage.stop(message.id)

    soon = %{message | closes_at: DateTime.add(DateTime.utc_now(), 50, :millisecond)}
    :ok = OpenMessage.start(soon)

    assert_receive {:window_ended, id}, 1_000
    assert id == message.id
    assert Repo.reload!(message).state == "open"
  end

  @tag req: "GM-04"
  test "GM-04 after the window, Enter still commits to the same open message", %{
    topic: topic,
    author: author
  } do
    message = topic |> then(&commit!(author, &1, "One")) |> end_window!()

    later = commit!(author, topic, "One. Two")
    assert later.id == message.id
    assert later.state == "open"
    assert later.body_md == "One. Two."
  end

  @tag req: "GM-05"
  test "GM-05 Ctrl+Enter within the window keeps the next line in the same message", %{
    topic: topic,
    author: author
  } do
    message = commit!(author, topic, "One", break: true)
    assert message.state == "open"

    same = commit!(author, topic, "One.\nTwo")
    assert same.id == message.id
    assert same.body_md == "One.\nTwo."
  end

  @tag req: "GM-05"
  test "GM-05 Ctrl+Enter after the window closes the message; the next line starts a new one",
       %{topic: topic, author: author} do
    message = topic |> then(&commit!(author, &1, "One")) |> end_window!()
    # Someone wrote below it (else the unanswered time applies, tested below).
    commit!(user_fixture(), topic, "Reply")

    closed = commit!(author, topic, "One. Last words", break: true)
    assert closed.id == message.id
    assert closed.state == "closed"
    assert closed.body_md == "One. Last words."
    assert closed.closed_at
    refute OpenMessage.running?(message.id)

    next = commit!(author, topic, "New thought")
    refute next.id == message.id
    assert next.state == "open"
  end

  # Steward decision, 2026-10-23: the unanswered message time (`gm_unanswered_minutes`).
  @tag req: "GM-05"
  test "GM-05 with nobody below it, Ctrl+Enter completes a message only once it is old enough",
       %{topic: topic, author: author} do
    message = topic |> then(&commit!(author, &1, "Alone")) |> end_window!()

    # Ten minutes by default: Ctrl+Enter is a line of the same message until then.
    still = commit!(author, topic, "Alone. Still", break: true)
    assert still.id == message.id
    assert still.state == "open"
    assert Messages.unanswered_until(still) == DateTime.add(still.opened_at, 600, :second)

    # A message deleted below it does not count as an answer.
    {:ok, reply} = Messages.commit(user_fixture(), topic, "Spam")
    {:ok, _} = Messages.delete_as_moderator(user_with_role_fixture(:administrator), reply, "x")
    reply = Repo.reload!(reply)
    {:ok, _} = Messages.close(reply)
    assert commit!(author, topic, "Alone. Still. Again", break: true).state == "open"

    # Older than the time: it completes, answered or not.
    still
    |> Ecto.Changeset.change(opened_at: DateTime.add(DateTime.utc_now(), -601, :second))
    |> Repo.update!()

    assert commit!(author, topic, "Alone. Still. Again. Done", break: true).state == "closed"
  end

  @tag req: "GM-09"
  test "GM-09 an author has at most one open message per topic", %{
    topic: topic,
    author: author
  } do
    one = commit!(author, topic, "One")
    other = commit!(user_fixture(), topic, "Someone else")
    again = commit!(author, topic, "One. Two")

    assert again.id == one.id
    refute other.id == one.id

    # The database refuses a second open message too.
    now = DateTime.utc_now()
    id = Idejo.Federation.generate_id()

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%Message{
        id: id,
        uri: Idejo.Federation.uri(:message, id),
        topic_id: topic.id,
        author_id: author.id,
        state: "open",
        opened_at: now,
        closes_at: now,
        body_md: "x",
        body_html: "x"
      })
    end
  end

  @tag req: "GM-14"
  test "GM-14 the first message of a topic is never open", %{topic: topic, author: author} do
    [first] = Forum.list_messages(topic)
    assert first.state == "closed"

    # The first live message is a new one, not the topic's first.
    message = commit!(author, topic, "Hello")
    refute message.id == first.id
    assert Repo.reload!(first).state == "closed"
  end

  @tag req: "GM-13"
  test "GM-13 a growing message counts as one message in its topic", %{
    general: general,
    topic: topic,
    author: author
  } do
    commit!(author, topic, "One")
    commit!(author, topic, "One. Two")
    commit!(author, topic, "One. Two. Three", break: true)
    commit!(author, topic, "One. Two. Three.\nFour")

    assert Repo.reload!(topic).message_count == 2
    assert length(Forum.list_messages(topic)) == 2
    assert {[%{id: id, message_count: 2}], false} = Forum.list_topics(general)
    assert id == topic.id
    # Notifications, unread counts and search follow with M4 (NO, TP-07, SE).
  end

  @tag req: "NF-02"
  test "NF-02 a commit is in the database before it is acknowledged", %{
    topic: topic,
    author: author
  } do
    {:ok, message} = Messages.commit(author, topic, "Durable")
    assert Repo.get!(Message, message.id).body_md == "Durable."

    assert_receive {:message, %Message{id: id}}
    assert Repo.get!(Message, id).body_md == "Durable."
  end

  @tag req: "NF-02"
  test "NF-02 after a restart open messages get their timer back with the original window", %{
    topic: topic,
    author: author
  } do
    open = commit!(author, topic, "Still open")
    ended = commit!(user_fixture(), topic, "Window over") |> end_window!()
    stop_timers()
    refute OpenMessage.running?(open.id)

    assert Recovery.run() == 1
    assert OpenMessage.running?(open.id)
    refute OpenMessage.running?(ended.id)

    assert Repo.reload!(open).closes_at == open.closes_at
    assert Repo.reload!(ended).state == "open"
  end

  @tag req: "GM-02"
  test "GM-02 an Enter with nothing typed and nothing open does nothing", %{
    topic: topic,
    author: author
  } do
    assert Messages.commit(author, topic, "   ") == {:ok, nil}
    refute_receive {:message, _}
  end

  @tag req: "GM-01"
  test "GM-01 posting live needs the post right and an open topic", %{
    topic: topic,
    author: author
  } do
    assert Messages.commit(unconfirmed_user_fixture(), topic, "x") == {:error, :forbidden}

    topic |> Ecto.Changeset.change(state: "locked") |> Repo.update!()
    assert Messages.commit(author, topic, "x") == {:error, :forbidden}
  end

  @tag req: "GM-01"
  test "GM-01 an opening Enter can reply to a message of the topic (TP-08)", %{
    topic: topic,
    author: author
  } do
    [first] = Forum.list_messages(topic)
    message = commit!(author, topic, "Agreed", reply_to_id: first.id)
    assert message.reply_to_id == first.id
  end
end

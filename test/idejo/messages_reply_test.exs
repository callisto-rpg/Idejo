# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Reply starts a new message (steward decision, 2026-10-24): `Messages.commit/4` with `new:`.
# Not async: one test turns the `gm_early_reply` setting off.
defmodule Idejo.MessagesReplyTest do
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.Message
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Chat", "body" => "Hi all"})
    [first] = Forum.list_messages(topic)
    author = user_fixture()
    Messages.subscribe(topic.id)

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, topic: topic, first: first, author: author}
  end

  @tag req: "TP-08"
  test "TP-08 a reply is a new message, even while the open message's timer runs", %{
    topic: topic,
    first: first,
    author: author
  } do
    {:ok, open} = Messages.commit(author, topic, "Still talking")
    assert_receive {:message, %Message{state: "open"}}
    assert Settings.get(:gm_early_reply) == true

    {:ok, reply} =
      Messages.commit(author, topic, "About that", new: true, reply_to_id: first.id)

    assert reply.id != open.id
    assert reply.state == "open"
    assert reply.reply_to_id == first.id
    assert reply.body_md == "About that."

    # The open message closed first, unchanged, and viewers heard of it before the reply.
    closed = Repo.get!(Message, open.id)
    assert closed.state == "closed"
    assert closed.body_md == "Still talking."
    assert_receive {:message, %Message{id: id, state: "closed"}}
    assert id == open.id
    assert_receive {:message, %Message{id: reply_id, state: "open"}}
    assert reply_id == reply.id
    assert Repo.reload!(topic).message_count == 3
  end

  @tag req: "TP-08"
  test "TP-08 without a reply, a new message waits for the timer like Ctrl+Enter", %{
    topic: topic,
    author: author
  } do
    {:ok, open} = Messages.commit(author, topic, "Still talking")

    assert {:error, :too_soon} = Messages.commit(author, topic, "Something else", new: true)
    assert Repo.get!(Message, open.id).state == "open"
    assert [_, _] = Forum.list_messages(topic)

    # Once Ctrl+Enter could start one (window over and someone wrote below), it is sent.
    open
    |> Ecto.Changeset.change(
      closes_at: DateTime.add(DateTime.utc_now(), -1, :second),
      opened_at: DateTime.add(DateTime.utc_now(), -601, :second)
    )
    |> Repo.update!()

    {:ok, next} = Messages.commit(author, topic, "Something else", new: true)
    assert next.id != open.id
    assert Repo.get!(Message, open.id).state == "closed"
  end

  @tag req: "TP-08"
  test "TP-08 with early replies off, a reply waits for the timer too", %{
    admin: admin,
    topic: topic,
    first: first,
    author: author
  } do
    {:ok, _} = Settings.update_settings(admin, %{"gm_early_reply" => "false"})
    assert Settings.get(:gm_early_reply) == false
    {:ok, open} = Messages.commit(author, topic, "Still talking")

    assert {:error, :too_soon} =
             Messages.commit(author, topic, "About that", new: true, reply_to_id: first.id)

    assert Repo.get!(Message, open.id).state == "open"
  end

  @tag req: "TP-08"
  test "TP-08 with nothing open, new: is an ordinary first Enter", %{
    topic: topic,
    first: first,
    author: author
  } do
    {:ok, reply} = Messages.commit(author, topic, "Hello", new: true, reply_to_id: first.id)
    assert reply.state == "open"
    assert reply.reply_to_id == first.id
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Rules out of the web layer (AP-01 preparation): the growing-message rules a topic view used
# to work out itself, and what `Messages.commit/4` refuses on its own, called directly with
# what a client could send. Not async: one test changes server-wide settings.
defmodule Idejo.MessagesRulesTest do
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Conversations
  alias Idejo.Forum
  alias Idejo.Forum.Forwards
  alias Idejo.Messages
  alias Idejo.Messages.{Message, Polls}
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Chat", "body" => "Hi all"})
    [first] = Forum.list_messages(topic)

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, starter: starter, topic: topic, first: first}
  end

  describe "the one formula for when a new message may start" do
    @tag req: "GM-05"
    test "GM-05 start_new_at/3 agrees with may_start_new?/2", %{topic: topic} do
      {:ok, message} = Messages.commit(user_fixture(), topic, "Alone")
      seconds = Messages.unanswered_seconds()

      lone = Messages.start_new_at(message, false, seconds)
      answered = Messages.start_new_at(message, true, seconds)

      assert answered == message.closes_at
      assert lone == DateTime.add(Messages.timer_start(message), seconds, :second)

      refute Messages.may_start_new?(message, DateTime.add(lone, -1, :second))
      assert Messages.may_start_new?(message, lone)

      # Once someone writes below it, the window's end is enough.
      {:ok, _} = Messages.commit(user_fixture(), topic, "Hello")
      assert Messages.may_start_new?(message, answered)
      refute Messages.may_start_new?(message, DateTime.add(answered, -1, :second))
    end

    @tag req: "GM-05"
    test "GM-05 answered_among?/2 counts only messages below it that are not deleted", %{
      topic: topic,
      admin: admin
    } do
      {:ok, mine} = Messages.commit(user_fixture(), topic, "Mine")
      {:ok, below} = Messages.commit(user_fixture(), topic, "Below")
      [first | _] = Forum.list_messages(topic)

      refute Messages.answered_among?([first, mine], mine)
      assert Messages.answered_among?([first, mine, below], mine)

      {:ok, deleted} = Messages.delete_as_moderator(admin, below)
      refute Messages.answered_among?([first, mine, deleted], mine)
    end

    @tag req: "GM-15"
    test "GM-15 window_seconds/1: the setting, none in a private conversation", %{topic: topic} do
      assert Messages.window_seconds(topic) == Settings.get(:gm_window_seconds)

      {:ok, private} = Conversations.start(user_fixture(), user_fixture())
      assert Messages.window_seconds(private) == 0
    end

    @tag req: "GM-05"
    test "GM-05 early_reply_allowed?/0 follows its setting", %{admin: admin} do
      assert Messages.early_reply_allowed?()
      {:ok, _} = Settings.update_settings(admin, %{"gm_early_reply" => "false"})
      refute Messages.early_reply_allowed?()
    end
  end

  describe "typing/2: the first keystroke, kept on the server" do
    @tag req: "GM-03"
    test "GM-03 the first keystroke's time is kept and starts the timers", %{topic: topic} do
      first = Messages.typing(topic, true)
      assert %DateTime{} = first
      # Typing again keeps the first keystroke.
      assert Messages.typing(topic, true) == first

      {:ok, message} = Messages.commit(user_fixture(), topic, "Hello")
      assert message.timer_from == first

      # Used once: the next message starts from its own keystroke, or its first commit.
      {:ok, next} = Messages.commit(user_fixture(), topic, "Next")
      assert DateTime.compare(next.timer_from, first) == :gt
    end

    @tag req: "GM-03"
    test "GM-03 an emptied box forgets the keystroke", %{topic: topic} do
      Messages.typing(topic, true)
      assert Messages.typing(topic, false) == nil

      before = DateTime.utc_now()
      {:ok, message} = Messages.commit(user_fixture(), topic, "Hello")
      assert DateTime.compare(message.timer_from, before) != :lt
    end

    @tag req: "GM-03"
    test "GM-03 another process's keystroke never counts", %{topic: topic} do
      Task.await(Task.async(fn -> Messages.typing(topic, true) end))
      Process.sleep(5)

      before = DateTime.utc_now()
      {:ok, message} = Messages.commit(user_fixture(), topic, "Hello")
      assert DateTime.compare(message.timer_from, before) != :lt
    end
  end

  describe "commit/4 refuses what a client could send" do
    @tag req: "GM-05"
    test "GM-05 a reply id that leads nowhere neither quotes nor starts a message early", %{
      topic: topic
    } do
      author = user_fixture()
      {:ok, open} = Messages.commit(author, topic, "Still talking")

      for bogus <- [Ecto.UUID.generate(), "not an id"] do
        assert {:error, :too_soon} =
                 Messages.commit(author, topic, "Sneaky", new: true, reply_to_id: bogus)

        assert {:error, :too_soon} =
                 Messages.commit(author, topic, "Sneaky", new: true, forwarded_from_id: bogus)
      end

      assert Repo.get!(Message, open.id).state == "open"
    end

    @tag req: "GM-05"
    test "GM-05 a message held by Ctrl+Enter is not skipped with a bogus reply id", %{
      topic: topic
    } do
      author = user_fixture()
      {:ok, _} = Messages.commit(author, topic, "Done early")
      {:ok, held} = Messages.commit(author, topic, "Done early.", break: true)
      assert held.held
      assert Messages.held_until(author, topic)

      assert {:error, :too_soon} =
               Messages.commit(author, topic, "Next", reply_to_id: Ecto.UUID.generate())
    end

    @tag req: "TP-08"
    test "TP-08 a reply to a deleted message or another topic's carries no reply", %{
      topic: topic,
      general: general,
      admin: admin
    } do
      {:ok, gone} = Messages.commit(user_fixture(), topic, "Soon gone", break: true)
      {:ok, _} = Messages.delete_as_moderator(admin, gone)

      {:ok, other} =
        Forum.create_topic(user_fixture(), general, %{"title" => "Other", "body" => "There"})

      [elsewhere] = Forum.list_messages(other)

      {:ok, reply} = Messages.commit(user_fixture(), topic, "To nothing", reply_to_id: gone.id)
      assert reply.reply_to_id == nil

      {:ok, reply} =
        Messages.commit(user_fixture(), topic, "Far away", reply_to_id: elsewhere.id)

      assert reply.reply_to_id == nil
    end

    @tag req: "TP-08"
    test "TP-08 a message still being written is not forwarded by its author", %{
      topic: topic,
      first: first
    } do
      author = user_fixture()
      {:ok, open} = Messages.commit(author, topic, "Not done")
      refute Forwards.may_forward?(author, open)

      # Not a forward, so not a new message before the timers run out either.
      assert {:error, :too_soon} =
               Messages.commit(author, topic, "Look", new: true, forwarded_from_id: open.id)

      # In another topic, the message opens without it.
      {:ok, elsewhere} =
        Forum.create_topic(user_fixture(), Repo.preload(topic, :category).category, %{
          "title" => "Elsewhere",
          "body" => "Here"
        })

      {:ok, forward} = Messages.commit(author, elsewhere, "Look", forwarded_from_id: open.id)
      assert forward.forwarded_from_id == nil

      # Someone else's message, readable, is forwarded as before.
      {:ok, again} = Messages.commit(user_fixture(), topic, "This", forwarded_from_id: first.id)
      assert again.forwarded_from_id == first.id
    end

    @tag req: "TP-08"
    test "TP-08 a message the author may not read is not forwarded", %{admin: admin, topic: topic} do
      {:ok, hidden} = Forum.create_category(admin, %{"name" => "Staff"})

      for role <- Idejo.Access.list_roles(),
          role.name in ~w(member guest),
          do: {:ok, _} = Idejo.Access.set_permission(admin, role, hidden, :view, :deny)

      {:ok, secret} =
        Forum.create_topic(admin, hidden, %{"title" => "Secret", "body" => "Staff only"})

      [message] = Forum.list_messages(secret)

      {:ok, forward} =
        Messages.commit(user_fixture(), topic, "Leak", forwarded_from_id: message.id)

      assert forward.forwarded_from_id == nil
      assert Forwards.source(user_fixture(), message.id) == nil
      assert %Message{} = Forwards.source(admin, message.id)
    end
  end

  describe "functions taking ids from a client" do
    @tag req: "TP-21"
    test "TP-21 a poll under an unknown or someone else's message is refused", %{
      topic: topic,
      first: first
    } do
      user = user_fixture()
      poll = %{"question" => "Which?", "options" => ["A", "B"], "hours" => "1"}

      assert {:error, :forbidden} = Polls.create(user, Ecto.UUID.generate(), poll)
      assert {:error, :forbidden} = Polls.create(user, "not an id", poll)
      assert {:error, :forbidden} = Polls.create(user, first.id, poll)

      {:ok, mine} = Messages.commit(user, topic, "Mine")
      assert {:ok, _summary} = Polls.create(user, mine.id, poll)
    end

    @tag req: "MO-02"
    test "MO-02 save_edit/4: the author edits, a member may not edit someone else's", %{
      first: first,
      starter: starter,
      admin: admin
    } do
      assert {:error, :forbidden} = Messages.save_edit(user_fixture(), first, "Mine now", nil)
      assert {:ok, %{body_md: "Edited"}} = Messages.save_edit(starter, first, "Edited", nil)

      assert {:ok, %{body_md: "By a moderator"}} =
               Messages.save_edit(admin, first, "By a moderator", "Tidy")
    end
  end
end

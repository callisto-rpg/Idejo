# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ModerationDeleteEditTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Moderation
  alias Idejo.Moderation.{Action, Report}
  alias Idejo.Notifications
  alias Idejo.Reading
  alias Idejo.Search

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Plans", "body" => "Hello"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{topic: topic, author: author, moderator: user_with_role_fixture(:moderator)}
  end

  @tag req: "MO-02"
  test "MO-02 a moderator deletes a message: it stays for moderators, logged", %{
    topic: topic,
    author: author,
    moderator: moderator
  } do
    {:ok, open} = Messages.commit(author, topic, "Rude and still typing")
    {:ok, _} = Moderation.report_message(user_fixture(), open, %{"reason" => "Rude"})
    count = Repo.reload!(topic).message_count

    {:ok, deleted} = Messages.delete_as_moderator(moderator, open, "Insults")
    assert deleted.state == "closed"
    assert deleted.deleted_by_id == moderator.id
    assert deleted.body_md == "Rude and still typing."
    assert Repo.reload!(topic).message_count == count - 1
    assert Repo.one!(Report).status == "resolved"

    assert [{"message.delete", "Insults"}] =
             Repo.all(from a in Action, select: {a.action, a.reason})

    # Deleting again does nothing; members and authors cannot.
    {:ok, _} = Messages.delete_as_moderator(moderator, deleted)
    assert Repo.aggregate(Action, :count) == 1
    {:ok, other} = Forum.post_message(user_fixture(), topic, %{"body" => "Fine"})
    assert Messages.delete_as_moderator(author, other) == {:error, :forbidden}
  end

  @tag req: "MO-02"
  test "MO-02 a deleted message leaves search, notifications, unread counts, reports and forks",
       %{topic: topic, author: author, moderator: moderator} do
    reader =
      user_fixture()
      |> Ecto.Changeset.change(created_at: DateTime.add(DateTime.utc_now(:second), -3600))
      |> Repo.update!()

    :ok = Reading.mark_read(reader, topic)
    {:ok, rude} = Forum.post_message(author, topic, %{"body" => "Zebracorn @#{reader.username}"})
    assert {[_], false} = Search.search(reader, "zebracorn")
    assert Notifications.unread_count(reader) == 1
    assert Reading.unread_counts(reader, [topic.id]) == %{topic.id => 1}

    {:ok, rude} = Messages.delete_as_moderator(moderator, rude)

    assert Search.search(reader, "zebracorn") == {[], false}
    assert Notifications.unread_count(reader) == 0
    assert Reading.unread_counts(reader, [topic.id]) == %{}
    assert Moderation.report_message(reader, rude, %{"reason" => "x"}) == {:error, :forbidden}

    {:ok, help} =
      Forum.create_category(user_with_role_fixture(:administrator), %{"name" => "Help"})

    assert Forum.create_topic(reader, help, %{"title" => "F", "body" => "B"}, forked_from: rude) ==
             {:error, :forbidden}

    assert Messages.edit(author, rude, "Sorry") == {:error, :forbidden}
  end

  @tag req: "MO-02"
  test "MO-02 a moderator edits someone's closed message, keeping the earlier version", %{
    topic: topic,
    author: author,
    moderator: moderator
  } do
    {:ok, posted} = Forum.post_message(author, topic, %{"body" => "Call me at 555-0100"})

    {:ok, edited} =
      Messages.edit_as_moderator(moderator, posted, "Call me [number removed]", "Personal data")

    assert edited.body_md == "Call me [number removed]"
    assert edited.edited
    assert [%{body_md: "Call me at 555-0100"}] = Messages.list_versions(edited)

    assert [{"message.edit", "Personal data"}] =
             Repo.all(from a in Action, select: {a.action, a.reason})

    {:ok, open} = Messages.commit(user_fixture(), topic, "Typing")
    assert Messages.edit_as_moderator(moderator, open, "x") == {:error, :open}
    assert Messages.edit_as_moderator(moderator, edited, "  ") == {:error, :blank}
    assert Messages.edit_as_moderator(author, edited, "Mine now") == {:error, :forbidden}

    {:ok, deleted} = Messages.delete_as_moderator(moderator, edited)
    assert Messages.edit_as_moderator(moderator, deleted, "y") == {:error, :deleted}
  end
end

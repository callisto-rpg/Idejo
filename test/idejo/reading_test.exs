# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ReadingTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.Message
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, topic: topic, reader: member_since(hours: -1)}
  end

  # A member who signed up `ago`, so the setup's messages came after.
  defp member_since(ago) do
    [hours: h] = ago
    user = user_fixture()

    user
    |> Ecto.Changeset.change(created_at: DateTime.add(DateTime.utc_now(:second), h * 3600))
    |> Repo.update!()
  end

  defp post!(topic, user \\ user_fixture(), body \\ "A reply") do
    {:ok, message} = Forum.post_message(user, topic, %{"body" => body})
    message
  end

  defp unread(user, topic), do: Reading.unread_counts(user, [topic.id])[topic.id]

  @tag req: "TP-07"
  test "TP-07 messages by others after the read position are unread; one's own never", %{
    topic: topic,
    reader: reader
  } do
    assert unread(reader, topic) == 1

    :ok = Reading.mark_read(reader, topic)
    assert unread(reader, topic) == nil

    post!(topic)
    post!(topic)
    post!(topic, reader, "Mine")
    assert unread(reader, topic) == 2

    :ok = Reading.mark_read(reader, topic)
    assert unread(reader, topic) == nil
    assert Reading.unread_counts(nil, [topic.id]) == %{}
  end

  @tag req: "TP-07"
  test "TP-07 first_unread is where a reader left off a topic they opened before", %{
    topic: topic,
    reader: reader
  } do
    # Never opened (no read position), and visitors: nowhere to go back to.
    assert Reading.first_unread(reader, topic) == nil
    assert Reading.first_unread(nil, topic) == nil

    :ok = Reading.mark_read(reader, topic)
    assert Reading.first_unread(reader, topic) == nil

    post!(topic, reader, "Mine")
    first = post!(topic)
    post!(topic)
    assert Reading.first_unread(reader, topic) == %{id: first.id, count: 2}

    :ok = Reading.mark_read(reader, topic)
    assert Reading.first_unread(reader, topic) == nil
  end

  @tag req: "TP-07"
  test "TP-07 a growing message is one unread item and does not turn unread as it grows", %{
    topic: topic,
    reader: reader
  } do
    :ok = Reading.mark_read(reader, topic)
    author = user_fixture()

    {:ok, _} = Messages.commit(author, topic, "One")
    {:ok, _} = Messages.commit(author, topic, "One. Two")
    assert unread(reader, topic) == 1

    :ok = Reading.mark_read(reader, topic)
    {:ok, _} = Messages.commit(author, topic, "One. Two. Three")
    {:ok, _} = Messages.commit(author, topic, "Changed. Two. Three")
    assert unread(reader, topic) == nil
  end

  @tag req: "TP-07"
  test "TP-07 a new member does not start with older topics unread", %{topic: topic} do
    Repo.update_all(from(m in Message, where: m.topic_id == ^topic.id),
      set: [opened_at: DateTime.add(DateTime.utc_now(), -7200)]
    )

    newcomer = user_fixture()
    assert unread(newcomer, topic) == nil

    post!(topic)
    assert unread(newcomer, topic) == 1
  end

  @tag req: "TP-07"
  test "TP-07 new since last visit lists unread topics the user may view, across categories",
       %{admin: admin, general: general, topic: topic, reader: reader} do
    {:ok, quiet} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Quiet", "body" => "Hello"})

    :ok = Reading.mark_read(reader, quiet)

    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff"})
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), staff, :view, :deny)

    {:ok, hidden} =
      Forum.create_topic(admin, staff, %{"title" => "Hidden", "body" => "Secret"})

    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})
    {:ok, other} = Forum.create_topic(user_fixture(), help, %{"title" => "Q", "body" => "?"})
    post!(other)

    {rows, false} = Reading.list_unread_topics(reader)
    ids = Enum.map(rows, fn {t, _count} -> t.id end)

    assert topic.id in ids
    assert other.id in ids
    refute quiet.id in ids
    refute hidden.id in ids
    assert {_, 2} = Enum.find(rows, fn {t, _} -> t.id == other.id end)
  end

  @tag req: "TP-07"
  test "TP-07 Unread pages topics with something new, newest first, each with its count", %{
    general: general,
    topic: topic,
    reader: reader
  } do
    # Read up to the last message, with two new ones since.
    :ok = Reading.mark_read(reader, topic)
    post!(topic)
    post!(topic)

    # Read, and nothing new since: not listed.
    {:ok, quiet} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Quiet", "body" => "."})

    :ok = Reading.mark_read(reader, quiet)

    # Never opened: unread since the reader signed up.
    {:ok, fresh} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Fresh", "body" => "."})

    post!(fresh)
    post!(fresh, reader)

    assert {[{first, 2}], true} = Reading.list_unread_topics(reader, per_page: 1)
    assert {[{second, 2}], false} = Reading.list_unread_topics(reader, per_page: 1, page: 2)
    assert [first.id, second.id] == [fresh.id, topic.id]
    assert {[], false} = Reading.list_unread_topics(reader, per_page: 1, page: 3)

    Reading.follow(reader, fresh)
    assert [{%{id: id}, 2}] = Reading.list_unread_followed_topics(reader)
    assert id == fresh.id
  end
end

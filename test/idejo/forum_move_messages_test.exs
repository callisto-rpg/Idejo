# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ForumMoveMessagesTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages
  alias Idejo.Messages.Message
  alias Idejo.Moderation.Action

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff room"})
    author = user_fixture()

    {:ok, topic} =
      Forum.create_topic(author, general, %{"title" => "Picnic", "body" => "Saturday?"})

    [opening] = Forum.list_messages(topic)
    {:ok, a} = Forum.post_message(user_fixture(), topic, %{"body" => "Off topic one"})

    {:ok, b} =
      Forum.post_message(author, topic, %{"body" => "Off topic two", "reply_to_id" => a.id})

    {:ok, c} =
      Forum.post_message(user_fixture(), topic, %{
        "body" => "Back on topic",
        "reply_to_id" => b.id
      })

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{
      admin: admin,
      general: general,
      staff: staff,
      topic: Repo.reload!(topic),
      opening: opening,
      a: a,
      b: b,
      c: c,
      moderator: user_with_role_fixture(:moderator)
    }
  end

  defp bodies(topic), do: topic |> Forum.list_messages() |> Enum.map(& &1.body_md)

  @tag req: "TP-15"
  test "TP-15 selected messages split into a new thread, the earliest opening it, logged", %{
    general: general,
    topic: topic,
    a: a,
    b: b,
    moderator: moderator
  } do
    Messages.subscribe(topic.id)

    {:ok, new} =
      Forum.move_messages(
        moderator,
        topic,
        [b.id, a.id],
        {:new, %{"title" => "Off topic", "category_id" => general.id}},
        "Split"
      )

    assert new.title == "Off topic"
    assert new.author_id == a.author_id
    assert bodies(new) == ["Off topic one", "Off topic two"]
    assert bodies(topic) == ["Saturday?", "Back on topic"]
    assert Repo.reload!(new).message_count == 2
    assert Repo.reload!(topic).message_count == 2

    assert_receive {:messages_moved, source_id}
    assert source_id == topic.id

    entry = Repo.get_by!(Action, action: "messages.move", target_id: topic.id)
    assert entry.reason == "Split"
    assert entry.details["to"]["id"] == new.id
    assert entry.details["count"] == 2

    assert Repo.exists?(
             from x in Activity, where: x.object_uri == ^a.uri and x.target_uri == ^new.uri
           )

    # The permalink of a moved message leads to its new thread.
    assert Forum.get_viewable_message(nil, a.id).topic_id == new.id
  end

  @tag req: "TP-15"
  test "TP-15 merged into an existing thread, they take their place by time", %{
    general: general,
    topic: topic,
    a: a,
    c: c,
    moderator: moderator
  } do
    {:ok, other} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Weather", "body" => "Rain?"})

    {:ok, _} = Forum.post_message(user_fixture(), other, %{"body" => "Later"})

    {:ok, merged} = Forum.move_messages(moderator, topic, [a.id, c.id], {:existing, other})
    assert merged.id == other.id

    # By time: the moved messages were written before this thread began.
    assert bodies(other) == ["Off topic one", "Back on topic", "Rain?", "Later"]

    assert Repo.reload!(other).message_count == 4
    assert Repo.reload!(topic).message_count == 2
  end

  @tag req: "TP-15"
  test "TP-15 an open message closes first; replies keep their link across threads", %{
    general: general,
    topic: topic,
    b: b,
    c: c,
    moderator: moderator
  } do
    writer = user_fixture()
    {:ok, open} = Messages.commit(writer, topic, "Still typing")

    {:ok, new} =
      Forum.move_messages(
        moderator,
        topic,
        [open.id, b.id],
        {:new, %{"title" => "Side", "category_id" => general.id}}
      )

    assert %Message{state: "closed", topic_id: topic_id} = Repo.reload!(open)
    assert topic_id == new.id

    assert Repo.exists?(
             from x in Action, where: x.action == "message.close" and x.target_id == ^open.id
           )

    # c, left behind, still replies to b, now in the new thread; b still replies to a.
    assert Repo.reload!(c).reply_to_id == b.id
    assert Repo.reload!(b).reply_to_id != nil
  end

  @tag req: "TP-15"
  test "TP-15 the opening message stays; the moderator needs both categories", %{
    admin: admin,
    general: general,
    staff: staff,
    topic: topic,
    opening: opening,
    a: a,
    moderator: moderator
  } do
    new = fn category -> {:new, %{"title" => "Split", "category_id" => category.id}} end

    assert {:error, :opening} =
             Forum.move_messages(moderator, topic, [opening.id, a.id], new.(general))

    assert {:error, :nothing} = Forum.move_messages(moderator, topic, [], new.(general))

    assert {:error, :not_found} =
             Forum.move_messages(moderator, topic, [Ecto.UUID.generate()], new.(general))

    assert {:error, :forbidden} =
             Forum.move_messages(user_fixture(), topic, [a.id], new.(general))

    assert {:error, %Ecto.Changeset{}} =
             Forum.move_messages(
               moderator,
               topic,
               [a.id],
               {:new, %{"title" => "", "category_id" => general.id}}
             )

    # A moderator of General only cannot move into the staff room.
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("General mods")})
    {:ok, _} = Access.set_permission(admin, role, general, :moderate, :allow)
    local = user_fixture()
    :ok = Access.grant_role(local, role)
    assert {:error, :forbidden} = Forum.move_messages(local, topic, [a.id], new.(staff))

    assert {:error, :invalid_target} =
             Forum.move_messages(moderator, topic, [a.id], {:existing, topic})

    assert Repo.reload!(a).topic_id == topic.id
    assert Repo.aggregate(from(t in Topic, where: t.title == "Split"), :count) == 0
  end

  @tag req: "TP-15"
  test "TP-15 targets: threads in moderated categories, by title or pasted link", %{
    admin: admin,
    general: general,
    staff: staff,
    topic: topic,
    moderator: moderator
  } do
    {:ok, weather} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Weather talk", "body" => "Rain?"})

    {:ok, secret} =
      Forum.create_topic(admin, staff, %{"title" => "Weather budget", "body" => "Shh"})

    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("General mods")})
    {:ok, _} = Access.set_permission(admin, role, general, :moderate, :allow)
    local = user_fixture()
    :ok = Access.grant_role(local, role)

    ids = fn user, query ->
      user |> Forum.search_move_targets(query, topic.id) |> Enum.map(& &1.id)
    end

    assert ids.(local, "weather") == [weather.id]
    assert Enum.sort(ids.(moderator, "WEATHER")) == Enum.sort([weather.id, secret.id])
    refute topic.id in ids.(moderator, "")
    assert ids.(local, "https://example.org/t/#{weather.id}/weather-talk") == [weather.id]
    assert ids.(local, "/t/#{secret.id}") == []
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ForumTopicModerationTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Moderation.Action

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Plans", "body" => "Hi"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{
      admin: admin,
      general: general,
      topic: topic,
      moderator: user_with_role_fixture(:moderator),
      member: user_fixture()
    }
  end

  defp actions,
    do: Repo.all(from a in Action, order_by: a.created_at, select: {a.action, a.reason})

  @tag req: "TP-14"
  test "TP-14 a moderator locks a topic: no new messages, open ones close, all logged", %{
    topic: topic,
    moderator: moderator,
    member: member
  } do
    Messages.subscribe(topic.id)
    {:ok, open} = Messages.commit(member, topic, "Typing")

    {:ok, locked} = Forum.moderate_topic(moderator, topic, :lock, "Heated")
    assert locked.state == "locked"
    assert Repo.reload!(open).state == "closed"
    assert_receive {:topic_changed, id}
    assert id == topic.id

    assert Messages.commit(member, locked, "More") == {:error, :forbidden}
    assert Forum.post_message(member, locked, %{"body" => "More"}) == {:error, :forbidden}
    refute Forum.can_post?(member, locked)

    assert {"topic.lock", "Heated"} in actions()

    assert Repo.exists?(
             from a in Activity, where: a.object_uri == ^topic.uri and a.verb == "update"
           )

    {:ok, unlocked} = Forum.moderate_topic(moderator, locked, :unlock)
    assert unlocked.state == "open"
    assert Forum.can_post?(member, unlocked)
    assert {"topic.unlock", nil} in actions()
  end

  @tag req: "TP-14"
  test "TP-14 pinned topics come first in their category", %{
    general: general,
    topic: topic,
    moderator: moderator,
    member: member
  } do
    {:ok, newer} = Forum.create_topic(member, general, %{"title" => "Newer", "body" => "Hi"})
    assert {[%{id: first}, _], false} = Forum.list_topics(general)
    assert first == newer.id

    {:ok, pinned} = Forum.moderate_topic(moderator, topic, :pin)
    assert pinned.pinned
    assert {[%{id: first}, _], false} = Forum.list_topics(general)
    assert first == topic.id

    {:ok, _} = Forum.moderate_topic(moderator, pinned, :unpin)
    assert Enum.map(actions(), &elem(&1, 0)) == ["topic.pin", "topic.unpin"]
  end

  @tag req: "TP-14"
  test "TP-14 only moderators of the category; archived topics stay archived", %{
    admin: admin,
    topic: topic,
    moderator: moderator,
    member: member
  } do
    assert Forum.moderate_topic(member, topic, :lock) == {:error, :forbidden}

    # Nothing changes, nothing is logged.
    {:ok, _} = Forum.moderate_topic(moderator, topic, :unlock)
    assert actions() == []

    # Archived as deleting its category would (TP-14, RP-03); set directly, so this async test
    # does not race others for the one shared Archive category.
    archived = topic |> Ecto.Changeset.change(state: "archived") |> Repo.update!()
    assert Forum.moderate_topic(admin, archived, :unlock) == {:error, :archived}
    assert {:ok, %{pinned: true}} = Forum.moderate_topic(admin, archived, :pin)
  end
end

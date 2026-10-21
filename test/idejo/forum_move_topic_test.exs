# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ForumMoveTopicTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Moderation.Action

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Oven", "body" => "Help?"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, help: help, topic: topic}
  end

  defp moderator_of(admin, categories) do
    {:ok, role} =
      Access.create_role(admin, %{"name" => "Mods #{System.unique_integer([:positive])}"})

    for c <- categories, do: {:ok, _} = Access.set_permission(admin, role, c, :moderate, :allow)
    user = user_fixture()
    :ok = Access.grant_role(user, role)
    user
  end

  @tag req: "TP-15"
  test "TP-15 a moderator moves a topic; its messages and links go with it, logged", %{
    admin: admin,
    general: general,
    help: help,
    topic: topic
  } do
    moderator = moderator_of(admin, [general, help])
    {:ok, open} = Messages.commit(user_fixture(), topic, "Still typing")
    Messages.subscribe(topic.id)

    {:ok, moved} = Forum.move_topic(moderator, topic, help, "Belongs in Help")
    assert moved.category_id == help.id
    assert_receive {:topic_changed, id}
    assert id == topic.id

    # Open messages stay open (GM-12); the topic is listed in its new category only.
    assert Repo.reload!(open).state == "open"
    assert {[%{id: ^id}], false} = Forum.list_topics(help)
    assert {[], false} = Forum.list_topics(general)

    entry = Repo.one!(Action)

    assert {entry.action, entry.reason, entry.category_id} ==
             {"topic.move", "Belongs in Help", general.id}

    assert entry.details == %{
             "from" => %{"id" => general.id, "name" => "General"},
             "to" => %{"id" => help.id, "name" => "Help"}
           }

    assert Repo.exists?(
             from a in Activity,
               where:
                 a.object_uri == ^topic.uri and a.verb == "update" and a.target_uri == ^help.uri
           )
  end

  @tag req: "TP-15"
  test "TP-15 the moderator needs the moderate right in both categories", %{
    admin: admin,
    general: general,
    help: help,
    topic: topic
  } do
    general_only = moderator_of(admin, [general])
    assert Forum.list_move_targets(general_only, topic) == []
    assert Forum.move_topic(general_only, topic, help) == {:error, :forbidden}

    assert Forum.move_topic(user_fixture(), topic, help) == {:error, :forbidden}
    assert Forum.move_topic(admin, topic, general) == {:error, :invalid_target}
    assert Enum.map(Forum.list_move_targets(admin, topic), & &1.name) == ["Help"]
    assert Repo.aggregate(Action, :count) == 0
  end
end

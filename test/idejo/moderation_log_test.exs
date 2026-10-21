# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ModerationLogTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Moderation
  alias Idejo.Moderation.Action

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})
    {:ok, topic} = Forum.create_topic(user_fixture(), general, %{"title" => "T", "body" => "Hi"})
    {:ok, help_topic} = Forum.create_topic(user_fixture(), help, %{"title" => "H", "body" => "?"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, help: help, topic: topic, help_topic: help_topic}
  end

  # A user who moderates only `category`, through a custom role.
  defp moderator_of(admin, category) do
    {:ok, role} =
      Access.create_role(admin, %{"name" => "Mods #{System.unique_integer([:positive])}"})

    {:ok, _} = Access.set_permission(admin, role, category, :moderate, :allow)
    user = user_fixture()
    :ok = Access.grant_role(user, role)
    user
  end

  defp open!(topic) do
    {:ok, message} = Messages.commit(user_fixture(), topic, "Still typing")
    message
  end

  @tag req: "MO-03"
  test "MO-03 a moderator action is logged with moderator, target, reason and time", %{
    admin: admin,
    general: general,
    topic: topic
  } do
    moderator = moderator_of(admin, general)
    message = open!(topic)

    {:ok, _} = Messages.close_as_moderator(moderator, message, "  Left open overnight  ")

    assert [%Action{} = entry] = Repo.all(Action)
    assert entry.moderator_id == moderator.id
    assert entry.action == "message.close"
    assert {entry.target_type, entry.target_id} == {"message", message.id}
    assert entry.category_id == general.id
    assert entry.reason == "Left open overnight"
    assert DateTime.diff(DateTime.utc_now(), entry.created_at) < 5

    # Nothing is logged when nothing is done.
    {:ok, _} = Messages.close_as_moderator(moderator, Repo.reload!(message))
    assert {:error, :forbidden} = Messages.close_as_moderator(user_fixture(), open!(topic))
    assert Repo.aggregate(Action, :count) == 1
  end

  @tag req: "MO-03"
  test "MO-03 the log is append-only", %{admin: admin, topic: topic} do
    {:ok, _} = Messages.close_as_moderator(admin, open!(topic))
    entry = Repo.one!(Action)

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      entry |> Ecto.Changeset.change(reason: "rewritten") |> Repo.update()
    end

    assert_raise Postgrex.Error, ~r/append-only/, fn -> Repo.delete(entry) end
  end

  @tag req: "MO-03"
  test "MO-03 moderators see the actions in their categories; administrators see all", %{
    admin: admin,
    general: general,
    topic: topic,
    help_topic: help_topic
  } do
    general_mod = moderator_of(admin, general)
    {:ok, _} = Messages.close_as_moderator(general_mod, open!(topic))
    {:ok, _} = Messages.close_as_moderator(admin, open!(help_topic))

    assert {[%{category_id: id}], false} = Moderation.list(general_mod)
    assert id == general.id
    assert {all, false} = Moderation.list(admin)
    assert length(all) == 2

    assert Moderation.moderator?(general_mod)
    assert Moderation.moderator?(admin)
    refute Moderation.moderator?(user_fixture())
    refute Moderation.moderator?(nil)
  end
end

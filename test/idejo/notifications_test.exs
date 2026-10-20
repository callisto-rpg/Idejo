# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.NotificationsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Notifications
  alias Idejo.Notifications.Notification
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    ada = user_fixture(%{username: "ada", display_name: "Ada"})
    bo = user_fixture(%{username: "bo_b", display_name: "Bo"})
    cy = user_fixture(%{username: "cy_c", display_name: "Cy"})
    {:ok, topic} = Forum.create_topic(ada, general, %{"title" => "Plans", "body" => "Tonight?"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, ada: ada, bo: bo, cy: cy, topic: topic}
  end

  defp kinds(message) do
    Repo.all(
      from n in Notification, where: n.message_id == ^message.id, select: {n.user_id, n.kind}
    )
    |> Map.new()
  end

  @tag req: "NO-01"
  test "NO-01 a new message notifies those it mentions, the one it replies to and followers",
       %{ada: ada, bo: bo, cy: cy, topic: topic} do
    [first] = Forum.list_messages(topic)
    dee = user_fixture()
    :ok = Reading.follow(dee, topic)

    {:ok, reply} =
      Forum.post_message(bo, topic, %{"body" => "Yes! cc @cy_c", "reply_to_id" => first.id})

    # Ada (starter, so a follower) is replied to; Cy is mentioned; Dee follows; never Bo.
    assert kinds(reply) == %{ada.id => "reply", cy.id => "mention", dee.id => "follow"}

    # Someone in several groups gets one notification, of the first kind: mention.
    {:ok, again} = Forum.post_message(cy, topic, %{"body" => "@ada", "reply_to_id" => reply.id})
    assert kinds(again)[ada.id] == "mention"
    assert kinds(again)[bo.id] == "reply"
    refute Map.has_key?(kinds(again), cy.id)
  end

  @tag req: "NO-02"
  test "NO-02 a growing message produces one notification (M4 exit check)", %{
    ada: ada,
    bo: bo,
    cy: cy,
    topic: topic
  } do
    :ok = Reading.follow(bo, topic)
    {:ok, open} = Messages.commit(ada, topic, "First line")
    assert kinds(open) == %{bo.id => "follow"}

    for n <- 1..10, do: {:ok, _} = Messages.commit(ada, topic, "First line. More #{n}")
    assert kinds(open) == %{bo.id => "follow"}

    # An append notifies only someone newly mentioned; Bo's follow becomes that mention.
    {:ok, _} = Messages.commit(ada, topic, "First line. More 10. Hey @bo_b")
    assert kinds(open) == %{bo.id => "mention"}
    {:ok, _} = Messages.commit(ada, topic, "First line. More 10. Hey @bo_b and @cy_c")
    assert kinds(open) == %{bo.id => "mention", cy.id => "mention"}

    # Read, it stays read when later appends mention Bo again.
    :ok = Notifications.mark_all_read(bo)
    {:ok, _} = Messages.commit(ada, topic, "First line. More 10. Hey @bo_b and @cy_c. @bo_b!")
    assert Notifications.unread_count(bo) == 0
    assert Repo.aggregate(from(n in Notification, where: n.user_id == ^bo.id), :count) == 1
  end

  @tag req: "NO-02"
  test "NO-02 editing a closed message notifies someone newly mentioned", %{
    ada: ada,
    cy: cy,
    topic: topic
  } do
    {:ok, posted} = Forum.post_message(ada, topic, %{"body" => "Who is in?"})
    {:ok, edited} = Messages.edit(ada, posted, "Who is in, @cy_c?")
    assert kinds(edited)[cy.id] == "mention"
  end

  @tag req: "NO-01"
  test "NO-01 nobody is notified of a topic they may not view", %{
    admin: admin,
    ada: ada,
    bo: bo,
    general: general,
    topic: topic
  } do
    :ok = Reading.follow(bo, topic)
    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "Before"})
    assert Notifications.unread_count(bo) == 1

    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), general, :view, :deny)
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), general, :view, :deny)

    {:ok, after_} = Forum.post_message(ada, topic, %{"body" => "After, @bo_b"})
    assert kinds(after_) == %{}
    # And earlier ones are no longer shown.
    assert Notifications.unread_count(bo) == 0
    assert {[], false} = Notifications.list(bo)
  end
end

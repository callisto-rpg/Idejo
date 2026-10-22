# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ReactionsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Notifications
  alias Idejo.Notifications.Notification
  alias Idejo.Reactions

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Picnic", "body" => "Hi"})
    [message] = Forum.list_messages(topic)

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, author: author, topic: topic, message: message}
  end

  defp notification(author, message),
    do: Repo.get_by(Notification, user_id: author.id, message_id: message.id, kind: "reaction")

  @tag req: "TP-17"
  test "TP-17 a click adds a reaction, another takes it back; several emoji per user", %{
    message: message
  } do
    ada = user_fixture()
    bea = user_fixture()
    Messages.subscribe(message.topic_id)

    assert {:ok, [%{emoji: "joy", count: 1}]} = Reactions.toggle(ada, message, "joy")
    assert_receive {:reactions, id, [%{emoji: "joy"}]}
    assert id == message.id

    {:ok, _} = Reactions.toggle(bea, message, "joy")
    # Other names of the same emoji are the same reaction.
    {:ok, summary} = Reactions.toggle(ada, message, "agree")
    assert [%{emoji: "joy", count: 2, user_ids: ids}, %{emoji: "agree", count: 1}] = summary
    assert ids == [ada.id, bea.id]

    {:ok, summary} = Reactions.toggle(ada, message, "joy")
    assert [%{emoji: "joy", count: 1}, %{emoji: "agree"}] = summary
    {:ok, _} = Reactions.toggle(ada, message, "+1")
    assert Enum.map(Reactions.summary(message.id), & &1.emoji) == ["joy", "agree", "+1"]

    assert {:error, :unknown_emoji} = Reactions.toggle(ada, message, "nothing_here")
  end

  @tag req: "TP-17"
  test "TP-17 any signed-in, verified reader reacts; not in read-only topics or deleted messages",
       %{admin: admin, general: general, topic: topic, message: message} do
    unverified = user_fixture() |> Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()
    refute Reactions.may_react?(nil, message)
    refute Reactions.may_react?(unverified, message)

    # A reader who may view but not post still reacts.
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), general, :post, :deny)
    reader = user_fixture()
    assert {:ok, _} = Reactions.toggle(reader, message, "heart")

    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), general, :view, :deny)
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), general, :view, :deny)
    assert {:error, :forbidden} = Reactions.toggle(reader, message, "heart")

    {:ok, _} = Forum.moderate_topic(admin, topic, :lock)
    assert {:error, :forbidden} = Reactions.toggle(admin, message, "heart")
    {:ok, _} = Forum.moderate_topic(admin, topic, :unlock)

    {:ok, gone} = Forum.post_message(admin, topic, %{"body" => "Spam"})
    {:ok, gone} = Messages.delete_as_moderator(admin, gone, "Spam")
    assert {:error, :forbidden} = Reactions.toggle(admin, gone, "heart")
  end

  @tag req: "TP-17"
  test "TP-17 the author gets one notification per message, unread again on new reactions", %{
    author: author,
    message: message
  } do
    ada = user_fixture()
    bea = user_fixture()

    # Reacting to one's own message notifies nobody.
    {:ok, _} = Reactions.toggle(author, message, "joy")
    refute notification(author, message)

    {:ok, _} = Reactions.toggle(ada, message, "joy")
    {:ok, _} = Reactions.toggle(ada, message, "heart")
    assert Repo.aggregate(from(n in Notification, where: n.user_id == ^author.id), :count) == 1

    :ok = Notifications.mark_all_read(author)
    {:ok, _} = Reactions.toggle(bea, message, "joy")
    assert notification(author, message).read_at == nil

    {[listed], false} = Notifications.list(author)
    assert listed.kind == "reaction"
    assert listed.reactions == 3

    assert IdejoWeb.NotificationHTML.headline(listed) ==
             "Your message in “Picnic” has 3 reactions"

    # When nobody else's reaction is left, the notification goes.
    for {user, emoji} <- [{ada, "joy"}, {ada, "heart"}, {bea, "joy"}],
        do: {:ok, _} = Reactions.toggle(user, message, emoji)

    refute notification(author, message)
  end
end

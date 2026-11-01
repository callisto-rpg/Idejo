# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Automessages (steward decision, 2026-11-01): moderators' !commands that the server posts.
defmodule Idejo.AutomessagesTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Accounts
  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Messages.Automessages
  alias Idejo.Moderation.Action
  alias Idejo.Notifications.Notification
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture()
    {:ok, topic} = Forum.create_topic(member, general, %{"title" => "Hi", "body" => "Hello"})
    %{admin: admin, general: general, member: member, topic: topic}
  end

  defp create(admin, attrs, picture \\ nil) do
    Automessages.create(
      admin,
      Map.merge(
        %{"command" => "rules", "body_md" => "Be **kind**.", "sender_username" => sender()},
        attrs
      ),
      picture
    )
  end

  defp sender, do: unique_username("bot")

  test "the default sender is idejo, with the Idejo picture, an account nobody signs in to", %{
    admin: admin
  } do
    assert Automessages.change().changes == %{} and
             Automessages.change().data.sender_username == "idejo"

    {:ok, automessage} = create(admin, %{"command" => "!Rules", "sender_username" => "idejo"})
    assert automessage.command == "rules"
    assert automessage.body_html =~ "<strong>kind</strong>"

    sender = Accounts.get_user!(automessage.sender_id)
    assert %{username: "idejo", display_name: "idejo", status: "system"} = sender
    assert sender.avatar_id
    assert sender.confirmed_at == nil
    refute Accounts.get_user_by_email_and_password(sender.email, "")

    assert [%{change: "automessage.create", after: %{"command" => "rules", "sender" => "idejo"}}] =
             Enum.filter(Audit.list_entries(), &(&1.change == "automessage.create"))
  end

  test "commands are unique, never the composer's own, and senders never a member's name", %{
    admin: admin,
    member: member
  } do
    {:ok, _} = create(admin, %{})

    {:error, changeset} = create(admin, %{"command" => "RULES"})
    assert "is already an automessage" in errors_on(changeset).command

    for own <- Automessages.reserved() do
      {:error, changeset} = create(admin, %{"command" => own})
      assert "is one of the composer's own commands" in errors_on(changeset).command
    end

    {:error, changeset} = create(admin, %{"command" => "two words"})
    assert errors_on(changeset).command != []

    {:error, changeset} =
      create(admin, %{"command" => "faq", "sender_username" => member.username})

    assert "belongs to a member" in errors_on(changeset).sender_username
  end

  test "the reserved names are the composer's own commands" do
    assert Automessages.reserved() == Enum.map(IdejoWeb.ComposerCommands.all(), & &1.name)
  end

  test "automessages with the same sender share its account; a picture uploaded replaces it",
       %{admin: admin} do
    name = sender()
    {:ok, rules} = create(admin, %{"sender_username" => name})
    {:ok, faq} = create(admin, %{"command" => "faq", "sender_username" => name}, image_file(:png))
    assert rules.sender_id == faq.sender_id
    assert faq.sender.avatar_id != rules.sender.avatar_id

    {:ok, moved} = Automessages.update(admin, faq, %{"sender_username" => sender()})
    assert moved.sender_id != rules.sender_id
    # The old account stays, for the messages it sent.
    assert Accounts.get_user!(rules.sender_id)
  end

  test "a moderator posts an automessage, as its sender, logged and notified", %{
    admin: admin,
    member: member,
    topic: topic
  } do
    {:ok, automessage} = create(admin, %{"body_md" => "Read the rules, @#{member.username}."})
    moderator = user_with_role_fixture(:moderator)
    Reading.auto_follow(member.id, topic.id)

    {:ok, message} = Automessages.post(moderator, topic, "rules")
    assert message.author_id == automessage.sender_id
    assert message.state == "closed"
    assert message.body_html =~ ~s(href="/u/#{member.id}")
    assert Repo.get!(Idejo.Forum.Topic, topic.id).message_count == 2

    assert [%{moderator_id: moderator_id, details: %{"command" => "rules"}}] =
             Repo.all(from a in Action, where: a.action == "message.automessage")

    assert moderator_id == moderator.id

    assert [%{kind: "mention"}] =
             Repo.all(from n in Notification, where: n.message_id == ^message.id)
  end

  test "only moderators of the category may post one, in open topics", %{
    admin: admin,
    member: member,
    topic: topic
  } do
    {:ok, _} = create(admin, %{})
    assert {:error, :forbidden} = Automessages.post(member, topic, "rules")
    assert {:error, :not_found} = Automessages.post(admin, topic, "nothing")
    assert {:ok, _} = Automessages.post(admin, topic, "rules")

    {:ok, locked} = Forum.moderate_topic(admin, topic, :lock, nil)
    assert {:error, :forbidden} = Automessages.post(admin, locked, "rules")
  end

  test "deleting an automessage keeps its sender's messages", %{admin: admin, topic: topic} do
    {:ok, automessage} = create(admin, %{})
    {:ok, message} = Automessages.post(admin, topic, "rules")
    {:ok, _} = Automessages.delete(admin, automessage)
    assert Automessages.list() == []
    assert Repo.get!(Idejo.Messages.Message, message.id).author_id == automessage.sender_id
  end
end

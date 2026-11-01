# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Automessages (steward decisions, 2026-11-01): !commands whose text the server posts.
defmodule Idejo.AutomessagesTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.Automessages
  alias Idejo.Messages.Automessages.Defaults
  alias Idejo.Moderation.Action
  alias Idejo.Notifications.Notification
  alias Idejo.Reading
  alias Idejo.Uploads

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture()
    {:ok, topic} = Forum.create_topic(member, general, %{"title" => "Hi", "body" => "Hello"})
    %{admin: admin, general: general, member: member, topic: topic, command: command()}
  end

  # Commands and senders of their own: async tests share only the defaults' rows.
  defp command, do: "cmd-#{System.unique_integer([:positive])}"
  defp sender, do: unique_username("bot")

  defp create(admin, attrs, picture \\ nil) do
    Automessages.create(
      admin,
      Map.merge(
        %{"command" => command(), "body_md" => "Be **kind**.", "sender_username" => sender()},
        attrs
      ),
      picture
    )
  end

  test "every install starts with the defaults, sent by idejo with the Idejo picture" do
    defaults = Map.new(Automessages.list(), &{&1.command, &1})

    for {command, body} <- Defaults.all() do
      assert %{body_md: ^body, everyone: false, cooldown_minutes: 0, sender: sender} =
               defaults[command]

      assert %{username: "idejo", status: "system", avatar_id: nil} = sender
      assert Uploads.avatar_url(sender) == "/images/idejo-pfp.png"
    end

    assert defaults["tutorial-message"].body_md =~ "(/help)"
    assert defaults["tutorial-commands"].body_md =~ "`!schedule`"
  end

  test "a new automessage's sender is idejo by default, an account nobody signs in to", %{
    admin: admin
  } do
    assert Automessages.change().data.sender_username == "idejo"
    name = command()

    {:ok, automessage} =
      create(admin, %{"command" => "!" <> String.upcase(name), "sender_username" => "idejo"})

    assert automessage.command == name
    sender = Accounts.get_user!(automessage.sender_id)
    assert %{username: "idejo", display_name: "idejo", status: "system"} = sender
    assert sender.confirmed_at == nil
    refute Accounts.get_user_by_email_and_password(sender.email, "")

    {:ok, other} = create(admin, %{})
    other_sender = Accounts.get_user!(other.sender_id)
    assert other_sender.status == "system" and other_sender.avatar_id == nil

    assert Enum.any?(
             Audit.list_entries(),
             &(&1.change == "automessage.create" and &1.after["command"] == name and
                 &1.after["sender"] == "idejo")
           )
  end

  test "commands are unique, never the composer's own, and senders never a member's name", %{
    admin: admin,
    member: member,
    command: name
  } do
    {:ok, _} = create(admin, %{"command" => name})

    {:error, changeset} = create(admin, %{"command" => String.upcase(name)})
    assert "is already an automessage" in errors_on(changeset).command

    for own <- Automessages.reserved() do
      {:error, changeset} = create(admin, %{"command" => own})
      assert "is one of the composer's own commands" in errors_on(changeset).command
    end

    {:error, changeset} = create(admin, %{"command" => "two words"})
    assert errors_on(changeset).command != []

    {:error, changeset} = create(admin, %{"sender_username" => member.username})
    assert "belongs to a member" in errors_on(changeset).sender_username

    {:error, changeset} = create(admin, %{"cooldown_minutes" => "-1"})
    assert errors_on(changeset).cooldown_minutes != []
  end

  test "the reserved names are the composer's own commands" do
    assert Automessages.reserved() == Enum.map(IdejoWeb.ComposerCommands.all(), & &1.name)
  end

  test "automessages with the same sender share its account; a picture uploaded replaces it",
       %{admin: admin} do
    name = sender()
    {:ok, rules} = create(admin, %{"sender_username" => name})
    {:ok, faq} = create(admin, %{"sender_username" => name}, image_file(:png))
    assert rules.sender_id == faq.sender_id
    assert faq.sender.avatar_id
    assert Uploads.avatar_url(faq.sender) == "/uploads/#{faq.sender.avatar_id}.webp"

    {:ok, moved} = Automessages.update(admin, faq, %{"sender_username" => sender()})
    assert moved.sender_id != rules.sender_id
    # The old account stays, for the messages it sent.
    assert Accounts.get_user!(rules.sender_id)
  end

  test "a moderator posts an automessage, as its sender, logged and notified", %{
    admin: admin,
    member: member,
    topic: topic,
    command: name
  } do
    {:ok, automessage} =
      create(admin, %{"command" => name, "body_md" => "Read the rules, @#{member.username}."})

    moderator = user_with_role_fixture(:moderator)
    Reading.auto_follow(member.id, topic.id)

    {:ok, message} = Automessages.post(moderator, topic, name)
    assert message.author_id == automessage.sender_id
    assert message.automessage_id == automessage.id
    assert message.state == "closed"
    assert message.body_html =~ ~s(href="/u/#{member.id}")
    assert Repo.get!(Idejo.Forum.Topic, topic.id).message_count == 2

    assert [%{moderator_id: moderator_id, details: %{"command" => ^name}}] =
             Repo.all(
               from a in Action,
                 where: a.action == "message.automessage" and a.target_id == ^message.id
             )

    assert moderator_id == moderator.id

    assert [%{kind: "mention"}] =
             Repo.all(from n in Notification, where: n.message_id == ^message.id)
  end

  test "+role in an automessage notifies the role's members, whoever sends it", %{
    admin: admin,
    member: member,
    topic: topic,
    command: name
  } do
    # Only owners and administrators may tag this role.
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Players")})
    {:ok, _} = Access.assign_role(admin, member, role)
    slug = Access.role_slug(role)

    {:ok, _} =
      create(admin, %{
        "command" => name,
        "body_md" => "Game night, +#{slug}!",
        "everyone" => true
      })

    poster = user_fixture()
    {:ok, message} = Automessages.post(poster, topic, name)
    assert message.body_html =~ ~s(href="/r/#{slug}")

    assert [%{user_id: user_id, kind: "role_mention"}] =
             Repo.all(from n in Notification, where: n.message_id == ^message.id)

    assert user_id == member.id
  end

  test "moderators may post any automessage; others only those allowed to everyone", %{
    admin: admin,
    member: member,
    topic: topic,
    command: name
  } do
    {:ok, _} = create(admin, %{"command" => name})
    {:ok, open} = create(admin, %{"everyone" => true})

    assert {:error, :forbidden} = Automessages.post(member, topic, name)
    assert {:error, :forbidden} = Automessages.post(admin, topic, "nothing")
    assert {:ok, _} = Automessages.post(admin, topic, name)
    assert {:ok, _} = Automessages.post(member, topic, open.command)

    names = &Enum.map(Automessages.commands_for(&1, topic), fn c -> c.name end)
    assert name in names.(admin) and open.command in names.(admin)
    refute name in names.(member)
    assert open.command in names.(member)
    assert names.(nil) == []

    {:ok, locked} = Forum.moderate_topic(admin, topic, :lock, nil)
    assert {:error, :forbidden} = Automessages.post(admin, locked, name)
    assert Automessages.commands_for(admin, locked) == []
  end

  test "after a post, the command waits its minutes in that topic, for everyone", %{
    admin: admin,
    member: member,
    general: general,
    topic: topic,
    command: name
  } do
    {:ok, automessage} = create(admin, %{"command" => name, "cooldown_minutes" => "10"})
    {:ok, message} = Automessages.post(admin, topic, name)

    assert {:error, {:cooldown, until}} = Automessages.post(admin, topic, name)
    assert DateTime.diff(until, message.opened_at, :minute) == 10

    # Another topic is not held back.
    {:ok, other} = Forum.create_topic(member, general, %{"title" => "Two", "body" => "Hey"})
    assert {:ok, _} = Automessages.post(admin, other, name)

    # A deleted one no longer counts, nor one older than the wait.
    {:ok, _} = Messages.delete_as_moderator(admin, message, nil)
    assert {:ok, again} = Automessages.post(admin, topic, name)

    Repo.update_all(from(m in Idejo.Messages.Message, where: m.id == ^again.id),
      set: [opened_at: DateTime.add(DateTime.utc_now(), -11, :minute)]
    )

    assert {:ok, latest} = Automessages.post(admin, topic, name)

    {:ok, _} = Automessages.update(admin, automessage, %{"cooldown_minutes" => "0"})
    assert {:ok, _} = Automessages.post(admin, topic, name)
    assert latest.automessage_id == automessage.id
  end

  test "deleting an automessage keeps its sender's messages", %{
    admin: admin,
    topic: topic,
    command: name
  } do
    {:ok, automessage} = create(admin, %{"command" => name})
    {:ok, message} = Automessages.post(admin, topic, name)
    {:ok, _} = Automessages.delete(admin, automessage)
    refute Enum.any?(Automessages.list(), &(&1.id == automessage.id))
    message = Repo.get!(Idejo.Messages.Message, message.id)
    assert message.author_id == automessage.sender_id
    assert message.automessage_id == nil
  end
end

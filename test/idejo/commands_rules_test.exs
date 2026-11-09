# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Rules out of the web layer (AP-01 preparation): which composer commands an author may use,
# asked of `Idejo.Messages.Commands` as any client would, and plugin blocks attached by a
# message id from a client.
defmodule Idejo.CommandsRulesTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Conversations
  alias Idejo.Forum
  alias Idejo.Messages.{Automessages, Commands}
  alias Idejo.Plugins
  alias IdejoWeb.ComposerCommands

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Chat", "body" => "Hi all"})
    %{admin: admin, topic: topic, starter: starter}
  end

  defp names(commands), do: Enum.map(commands, & &1.name)

  @tag req: "TP-11"
  test "TP-11 the composer's own commands are listed once, for every caller" do
    assert Commands.builtin() == Automessages.reserved()
    assert Commands.builtin() == Enum.map(ComposerCommands.all(), & &1.name)
  end

  @tag req: "TP-11"
  test "TP-11 builtin_available/3: !image with uploads, !gif with GIFs, !new-topic with forks" do
    assert Commands.builtin_available(true, true, true) == Commands.builtin()

    refute "image" in Commands.builtin_available(false, true, true)
    refute "gif" in Commands.builtin_available(true, true, false)
    refute "new-topic" in Commands.builtin_available(true, false, true)
    assert "poll" in Commands.builtin_available(false, false, false)
  end

  @tag req: "TP-11"
  test "TP-11 available/2: nothing for a visitor, an unverified user or in a locked topic", %{
    admin: admin,
    topic: topic
  } do
    assert Commands.available(nil, topic) == []
    assert Commands.available(unconfirmed_user_fixture(), topic) == []

    {:ok, locked} = Forum.moderate_topic(admin, topic, :lock, nil)
    assert Commands.available(user_fixture(), locked) == []
  end

  @tag req: "TP-11"
  test "TP-11 available/2: a member gets the composer's commands, GIFs only while on", %{
    topic: topic
  } do
    commands = Commands.available(user_fixture(), topic)

    assert Enum.all?(commands, &(&1.kind in [:builtin, :automessage, :plugin]))
    assert "image" in names(commands)
    assert "new-topic" in names(commands)
    refute "gif" in names(commands)
  end

  @tag req: "TP-09"
  test "TP-09 can_fork?/2: never from a private conversation", %{topic: topic} do
    member = user_fixture()
    assert Forum.can_fork?(member, topic)
    refute Forum.can_fork?(nil, topic)

    {:ok, private} = Conversations.start(member, user_fixture())
    refute Forum.can_fork?(member, private)
    refute "new-topic" in names(Commands.available(member, private))
  end

  @tag req: "TP-11"
  test "TP-11 a plugin block under an unknown message id is refused", %{starter: starter} do
    assert {:error, :forbidden} =
             Plugins.attach(starter, Ecto.UUID.generate(), "youtube", %{"link" => "x"})

    assert {:error, :forbidden} = Plugins.attach(starter, "not an id", "youtube", %{})
  end
end

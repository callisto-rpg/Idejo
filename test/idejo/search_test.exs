# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.SearchTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Search

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{
        "title" => "Picnic plans",
        "body" => "Saturday at noon"
      })

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, help: help, topic: topic, member: user_fixture()}
  end

  defp found(user, text, opts \\ []) do
    {results, _more?} = Search.search(user, text, opts)
    Enum.map(results, & &1.message.id)
  end

  @tag req: "SE-01"
  test "SE-01 finds messages by their words and topics by their title", %{
    general: general,
    help: help,
    topic: topic,
    member: member
  } do
    [first] = Forum.list_messages(topic)
    {:ok, reply} = Forum.post_message(member, topic, %{"body" => "I bring sourdough bread"})

    {:ok, other} =
      Forum.create_topic(member, help, %{
        "title" => "Oven help",
        "body" => "My bread will not rise"
      })

    [other_first] = Forum.list_messages(other)

    assert found(member, "sourdough") == [reply.id]
    # A title match is found through the topic's first message only.
    assert found(member, "picnic") == [first.id]
    assert Enum.sort(found(member, "bread")) == Enum.sort([reply.id, other_first.id])
    assert found(member, "bread", category: help) == [other_first.id]
    assert found(member, "BREAD", category: general) == [reply.id]
    assert found(member, "\"will not rise\"") == [other_first.id]
    assert found(member, "bread -sourdough") == [other_first.id]
    assert found(member, "   ") == []
    assert found(member, "nothingmatches") == []
  end

  @tag req: "SE-02"
  test "SE-02 results only show what the searcher may view", %{
    admin: admin,
    member: member
  } do
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff"})

    {:ok, secret} =
      Forum.create_topic(admin, staff, %{"title" => "Budget", "body" => "Hidden zebra"})

    [hidden] = Forum.list_messages(secret)

    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), staff, :view, :deny)
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), staff, :view, :deny)

    assert found(member, "zebra") == []
    assert found(nil, "zebra") == []
    assert found(nil, "budget") == []
    assert found(admin, "zebra") == [hidden.id]
    assert found(member, "zebra", category: staff) == []
  end

  @tag req: "SE-03"
  test "SE-03 search finds a message by a word added in its last commit (M4 exit check)", %{
    topic: topic,
    member: member
  } do
    {:ok, open} = Messages.commit(member, topic, "We could meet")
    {:ok, _} = Messages.commit(member, topic, "We could meet. At the lake")
    {:ok, _} = Messages.commit(member, topic, "We could meet. At the lake by the lighthouse")

    # One document per message: found once, by the word of its last commit, while still open.
    assert found(member, "lighthouse") == [open.id]
    assert found(member, "meet") == [open.id]

    {:ok, _} = Messages.commit(member, topic, "We could gather. At the lake by the lighthouse")
    assert found(member, "meet") == []
    assert found(member, "gather") == [open.id]
  end

  @tag req: "SE-01"
  test "SE-01 excerpts mark the words found", %{topic: topic, member: member} do
    {:ok, _} = Forum.post_message(member, topic, %{"body" => "Bring <b>cake</b> and tea"})
    {[result], false} = Search.search(member, "cake")
    assert {:match, "cake"} in result.excerpt
    assert Enum.map_join(result.excerpt, &elem(&1, 1)) =~ "and tea"
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.MessagesEditTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    author = user_fixture()

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    {:ok, open} = Messages.commit(author, topic, "The meeting is on Monday")
    {:ok, closed} = Messages.close(open)
    Messages.subscribe(topic.id)
    %{admin: admin, topic: topic, author: author, closed: closed}
  end

  @tag req: "GM-10"
  test "GM-10 the author edits a closed message", %{author: author, closed: closed} do
    {:ok, edited} = Messages.edit(author, closed, "The meeting is on Tuesday.")

    assert edited.body_md == "The meeting is on Tuesday."
    assert edited.body_html =~ "Tuesday"
    assert edited.state == "closed"
    assert_receive {:message, %{id: id, body_md: "The meeting is on Tuesday."}}
    assert id == closed.id
  end

  @tag req: "GM-11"
  test "GM-11 changing earlier text keeps every previous version, with its time", %{
    author: author,
    closed: closed
  } do
    {:ok, _} = Messages.edit(author, closed, "The meeting is on Tuesday.")
    {:ok, edited} = Messages.edit(author, closed, "The meeting is on Wednesday.")

    assert edited.edited
    assert [first, second] = Messages.list_versions(edited)
    assert first.body_md == "The meeting is on Monday."
    assert second.body_md == "The meeting is on Tuesday."
    assert DateTime.compare(first.created_at, second.created_at) in [:lt, :eq]
  end

  @tag req: "TP-05"
  test "TP-05 a message that only grew keeps just its final text", %{
    topic: topic,
    author: author
  } do
    {:ok, _} = Messages.commit(author, topic, "First")
    {:ok, _} = Messages.commit(author, topic, "First. Second")
    {:ok, open} = Messages.commit(author, topic, "First. Second. Third")
    {:ok, closed} = Messages.close(open)

    assert closed.body_md == "First. Second. Third."
    refute closed.edited
    assert Messages.list_versions(closed) == []
    # One row for the whole message, none per commit.
    assert Enum.count(Forum.list_messages(topic), &(&1.author_id == author.id)) == 2
  end

  @tag req: "TP-05"
  test "TP-05 an edit keeps the history", %{author: author, closed: closed} do
    {:ok, edited} = Messages.edit(author, closed, "The meeting is on Tuesday.")
    {:ok, edited} = Messages.edit(author, edited, "The meeting is on Wednesday.")

    assert edited.edited

    assert Enum.map(Messages.list_versions(edited), & &1.body_md) == [
             "The meeting is on Monday.",
             "The meeting is on Tuesday."
           ]
  end

  @tag req: "GM-10"
  test "GM-10 adding text at the end is not an edit", %{author: author, closed: closed} do
    {:ok, longer} = Messages.edit(author, closed, "The meeting is on Monday. At ten.")

    assert longer.body_md == "The meeting is on Monday. At ten."
    refute longer.edited
    assert Messages.list_versions(longer) == []
  end

  @tag req: "GM-10"
  test "GM-10 only the author edits, only closed messages, only in open topics", %{
    admin: admin,
    topic: topic,
    author: author,
    closed: closed
  } do
    assert Messages.edit(user_fixture(), closed, "Mine now") == {:error, :forbidden}
    assert Messages.edit(admin, closed, "Mine now") == {:error, :forbidden}
    assert Messages.edit(author, closed, "   ") == {:error, :blank}

    {:ok, open} = Messages.commit(author, topic, "Still typing")
    assert Messages.edit(author, open, "Changed") == {:error, :forbidden}

    topic |> Ecto.Changeset.change(state: "locked") |> Repo.update!()
    assert Messages.edit(author, closed, "Too late") == {:error, :forbidden}

    assert Repo.reload!(closed).body_md == "The meeting is on Monday."
  end

  @tag req: "GM-11"
  test "GM-11 editing sent text in the composer keeps versions too", %{
    topic: topic,
    author: author
  } do
    {:ok, _} = Messages.commit(author, topic, "See you at nine")
    {:ok, open} = Messages.commit(author, topic, "See you at ten")

    assert open.edited
    assert [%{body_md: "See you at nine."}] = Messages.list_versions(open)
  end
end

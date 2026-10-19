# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.MessagesClosingTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.{Authors, OpenMessage}

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    author = user_fixture()
    {:ok, open} = Messages.commit(author, topic, "Still typing")
    Messages.subscribe(topic.id)

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, topic: topic, author: author, open: open}
  end

  # A stand-in for the author's live topic view: alive until told to stop.
  defp view(topic, author, grace_ms) do
    test = self()

    pid =
      spawn(fn ->
        Process.put(:"$callers", [test])
        Authors.present(topic.id, author.id, grace_ms: grace_ms)
        send(test, :present)
        receive do: (:stop -> :ok)
      end)

    assert_receive :present
    pid
  end

  defp stop(pid), do: send(pid, :stop)

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end

  defp state(message), do: Repo.reload!(message).state

  @tag req: "GM-12"
  test "GM-12 archiving a topic closes its open messages", %{
    admin: admin,
    general: general,
    open: open
  } do
    {:ok, _} = Forum.delete_category(admin, general, topics: :archive)

    assert state(open) == "closed"
    assert_receive {:message, %{id: id, state: "closed"}}
    assert id == open.id
    refute OpenMessage.running?(open.id)
  end

  @tag req: "GM-12"
  test "GM-12 moving a topic does not close its open messages", %{
    admin: admin,
    general: general,
    open: open
  } do
    {:ok, other} = Forum.create_category(admin, %{"name" => "Other"})
    {:ok, _} = Forum.delete_category(admin, general, topics: {:move, other})
    assert state(open) == "open"
  end

  @tag req: "GM-12"
  test "GM-12 the message closes once the author's session has been gone for the grace", %{
    topic: topic,
    author: author,
    open: open
  } do
    pid = view(topic, author, 50)
    assert Authors.present?(topic.id, author.id)
    stop(pid)

    assert eventually(fn -> state(open) == "closed" end)
    assert_receive {:message, %{id: id, state: "closed"}}, 1_000
    assert id == open.id
  end

  @tag req: "GM-12"
  test "GM-12 coming back within the grace keeps the message open", %{
    topic: topic,
    author: author,
    open: open
  } do
    first = view(topic, author, 200)
    stop(first)
    _again = view(topic, author, 200)

    Process.sleep(400)
    assert state(open) == "open"
  end

  @tag req: "GM-12"
  test "GM-12 closing one of two views keeps the message open", %{
    topic: topic,
    author: author,
    open: open
  } do
    one = view(topic, author, 50)
    _other = view(topic, author, 50)
    stop(one)

    Process.sleep(200)
    assert state(open) == "open"
    assert Authors.present?(topic.id, author.id)
  end

  @tag req: "GM-12"
  test "GM-12 after a restart an author who does not come back has the message closed", %{
    topic: topic,
    author: author,
    open: open
  } do
    # What Idejo.Messages.Recovery does for every open message at boot.
    test = self()

    Task.async(fn ->
      Process.put(:"$callers", [test])
      Authors.absent(topic.id, author.id, grace_ms: 50)
    end)
    |> Task.await()

    assert eventually(fn -> state(open) == "closed" end)
  end

  @tag req: "GM-16"
  test "GM-16 moderators close another user's open message; members cannot", %{
    open: open
  } do
    assert Messages.close_as_moderator(user_fixture(), open) == {:error, :forbidden}
    assert state(open) == "open"

    {:ok, closed} = Messages.close_as_moderator(user_with_role_fixture(:moderator), open)
    assert closed.state == "closed"
    refute OpenMessage.running?(open.id)
  end
end

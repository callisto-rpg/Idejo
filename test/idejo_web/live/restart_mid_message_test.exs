# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.RestartMidMessageTest do
  @moduledoc """
  M3 exit check (MVP §7): "a server restart mid-message loses nothing" (NF-02, CLAUDE.md
  growing-message invariants 1-4).

  The test restarts every in-memory part of the engine, as a reboot would: the author's live
  view goes away, then the window timers (`OpenMessageSupervisor` and its `Registry`) and the
  presence tracker (`Authors`) are stopped and started empty, and `Recovery` runs as at boot.
  The database is the only thing left. Not async: it restarts processes the whole app shares.
  """
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.{Message, OpenMessage, Recovery}
  alias Idejo.Repo

  # The engine's in-memory processes, in start order (Idejo.Application).
  @engine [Idejo.Messages.Registry, Idejo.Messages.OpenMessageSupervisor, Idejo.Messages.Authors]

  defp restart_engine do
    for child <- Enum.reverse(@engine),
        do: :ok = Supervisor.terminate_child(Idejo.Supervisor, child)

    for child <- @engine, do: {:ok, _} = Supervisor.restart_child(Idejo.Supervisor, child)
  end

  defp watch(conn, topic) do
    {:ok, lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    lv
  end

  defp enter(lv, body) do
    lv |> element("#composer") |> render_hook("commit", %{"body" => body, "break" => false})
    assert_reply(lv, reply)
    reply
  end

  @tag req: "NF-02"
  test "NF-02 a server restart mid-message loses nothing", %{conn: conn} do
    Process.flag(:trap_exit, true)
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    author = user_fixture(%{display_name: "Ada"})
    author_conn = log_in_user(conn, author)

    lv = watch(author_conn, topic)
    assert %{closed: false} = enter(lv, "Half a thought")
    assert %{closed: false} = enter(lv, "Half a thought. And the rest of it")
    before = Repo.get_by!(Message, topic_id: topic.id, author_id: author.id)
    assert OpenMessage.running?(before.id)

    # The server goes down: the author's view and every engine process are gone.
    # (Once it is idle: a process killed inside a query would take the test's shared sandbox
    # connection with it.)
    render(lv)
    ref = Process.monitor(lv.pid)
    Process.exit(lv.pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}
    restart_engine()
    refute OpenMessage.running?(before.id)

    # It boots again.
    assert Recovery.run() == 1

    # Every sent word is there, still open, with its original window and timer.
    after_ = Repo.reload!(before)
    assert after_.state == "open"
    assert after_.body_md == "Half a thought. And the rest of it."
    assert after_.closes_at == before.closes_at
    assert OpenMessage.running?(before.id)
    assert Messages.list_versions(after_) == []

    # A reader sees it whole; the author comes back to the same message in the composer and
    # carries on.
    reader = watch(build_conn(), topic)
    assert has_element?(reader, "#message-#{before.id}", "And the rest of it.")

    lv = watch(author_conn, topic)
    assert_push_event(lv, "composer_sent", %{body: "Half a thought. And the rest of it."})
    assert has_element?(lv, ~s(#composer[data-sent="Half a thought. And the rest of it."]))

    assert %{closed: false} = enter(lv, "Half a thought. And the rest of it. Back again")

    assert [%Message{id: id, state: "open", body_md: body}] =
             Repo.all(
               from m in Message, where: m.topic_id == ^topic.id and m.author_id == ^author.id
             )

    assert id == before.id
    assert body == "Half a thought. And the rest of it. Back again."
    assert has_element?(reader, "#message-#{before.id}", "Back again.")
  end
end

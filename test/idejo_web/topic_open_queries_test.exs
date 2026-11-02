# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicOpenQueriesTest do
  # Changes the read mark's wait for the whole app.
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum

  # The queries a process sends while `fun` runs, and those of `pid` (a LiveView).
  defp queries(fun) do
    me = self()
    handler = "open-queries-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      [:idejo, :repo, :query],
      fn _, _, _, _ ->
        send(me, {:query, self()})
      end,
      nil
    )

    result = fun.()
    :telemetry.detach(handler)
    {result, collect([])}
  end

  defp collect(pids) do
    receive do
      {:query, pid} -> collect([pid | pids])
    after
      50 -> pids
    end
  end

  # NF-04: 200 people opening a busy topic at once ran the database pool dry; an open asked
  # for the same roles some twenty times and the settings a key at a time (Idejo.Memo).
  @tag req: "NF-04"
  test "NF-04 opening a topic page reads each thing once", %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Busy", "body" => "Hi"})
    for i <- 2..40, do: Forum.post_message(author, topic, %{"body" => "Message #{i}."})
    me = user_fixture()
    conn = log_in_user(conn, me)

    {_html, page} =
      queries(fn -> html_response(get(conn, ~p"/t/#{topic.id}/#{topic.slug}"), 200) end)

    # 89 before Idejo.Memo.
    assert length(page) <= 55

    {{:ok, view, _}, mounted} =
      queries(fn ->
        live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})
      end)

    # The connected mount, in the LiveView's own process: 35 before.
    assert Enum.count(mounted, &(&1 == view.pid)) <= 24

    # Off again once the response went, for whatever this process does next.
    refute Idejo.Memo.on?()
  end

  # NF-04: when 30 people start writing in a topic 200 watch, each viewer looked up each new
  # author's role and marked each new message read at once: 12,000 queries in seconds.
  @tag req: "NF-04"
  test "NF-04 a new message costs a viewer no query, and its read mark waits", %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Forum.create_topic(admin, general, %{"title" => "Busy", "body" => "Hi"})
    viewer = user_fixture()

    previous = Application.get_env(:idejo, :read_mark_ms)
    Application.put_env(:idejo, :read_mark_ms, {60_000, 1})
    on_exit(fn -> Application.put_env(:idejo, :read_mark_ms, previous) end)

    {:ok, view, _html} =
      live_isolated(log_in_user(conn, viewer), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    newcomers = for _ <- 1..2, do: user_fixture()

    {_, sent} =
      queries(fn ->
        for author <- newcomers,
            do: {:ok, _} = Forum.post_message(author, topic, %{"body" => "Hello"})

        render(view)
      end)

    # Their roles came with the messages; the read mark is not written yet.
    refute Enum.member?(sent, view.pid)
    assert Idejo.Reading.first_unread(viewer, topic) != nil

    # Once for both, when its time comes.
    {_, sent} =
      queries(fn ->
        send(view.pid, :mark_read)
        render(view)
      end)

    assert Enum.count(sent, &(&1 == view.pid)) == 1
    assert Idejo.Reading.first_unread(viewer, topic) == nil
  end
end

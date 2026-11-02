# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicOpenQueriesTest do
  use IdejoWeb.ConnCase, async: true

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
end

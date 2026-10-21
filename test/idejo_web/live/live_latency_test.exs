# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.LiveLatencyTest do
  # Not async: it times work, so it runs alone.
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages

  @viewers 50
  @commits 20

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Busy", "body" => "Hi"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{topic: topic, author: author}
  end

  # The full measure, over the network on the minimum server with 200 people, is the load
  # test (load/run.sh, docs/load-testing.md). This keeps the server's own part in check on
  # every build: from the commit to every open view's process having handled it (rendered
  # the change and sent it on).
  @tag req: "NF-01"
  test "NF-01 a commit is rendered in 50 open views of the topic well within 200 ms", %{
    topic: topic,
    author: author
  } do
    views =
      for _ <- 1..@viewers do
        {:ok, view, _html} =
          live_isolated(log_in_user(build_conn(), user_fixture()), IdejoWeb.TopicLive,
            session: %{"topic_id" => topic.id}
          )

        view
      end

    times =
      for n <- 1..@commits do
        body = Enum.map_join(1..n, " ", &"Word zq#{&1}q.")
        started = System.monotonic_time(:microsecond)
        {:ok, _} = Messages.commit(author, topic, body)
        # Answers once the view's process has handled what reached it before.
        for view <- views, do: :sys.get_state(view.pid)
        System.monotonic_time(:microsecond) - started
      end

    # They did render it.
    for view <- Enum.take_random(views, 5), do: assert(render(view) =~ "zq#{@commits}q")

    p95 = times |> Enum.sort() |> Enum.at(trunc(0.95 * @commits)) |> div(1000)
    assert p95 < 200, "p95 #{p95} ms to handle a commit in #{@viewers} views"
  end
end

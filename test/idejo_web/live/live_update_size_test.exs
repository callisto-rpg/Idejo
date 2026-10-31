# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.LiveUpdateSizeTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Reactions

  # Messages already in the topic: an update must not cost more because of them.
  @earlier 40

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    authors = for _ <- 1..3, do: user_fixture()
    {:ok, topic} = Forum.create_topic(hd(authors), general, %{"title" => "Busy", "body" => "Hi"})

    for i <- 2..@earlier do
      {:ok, _} =
        Forum.post_message(Enum.at(authors, rem(i, 3)), topic, %{
          "body" => "Message #{i}, with **some** text and a [link](https://example.org/#{i})."
        })
    end

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    {:ok, view, _html} =
      live_isolated(log_in_user(build_conn(), user_fixture()), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    # What the view sends its browser: each update's diff.
    :erlang.trace(view.pid, true, [:send])

    %{topic: topic, view: view}
  end

  # The next diff the view sends, as the JSON that goes over the socket, in bytes.
  defp next_diff(%{pid: pid}) do
    assert_receive {:trace, ^pid, :send, %Phoenix.Socket.Message{event: "diff", payload: diff},
                    _to}

    byte_size(Jason.encode!(diff))
  end

  # Every viewer handles every Enter (NF-01): each entry of the list reads only its own
  # message and what belongs to it, so an update renders and sends the entry it changed, not
  # the other #{@earlier}. Before, every entry went out again with each update.
  @tag req: "NF-01"
  test "NF-01 an Enter sends viewers the message it changed, not the whole topic", %{
    topic: topic,
    view: view
  } do
    writer = user_fixture()
    {:ok, _} = Messages.commit(writer, topic, "Hello")
    next_diff(view)

    {:ok, _} = Messages.commit(writer, topic, "Hello. And more")
    assert next_diff(view) < 1_000

    {:ok, _} = Messages.commit(writer, topic, "Hello. And more. And again")
    assert next_diff(view) < 1_000
  end

  @tag req: "NF-01"
  test "NF-01 a reaction sends viewers the message it changed, not the whole topic", %{
    topic: topic,
    view: view
  } do
    [first | _] = Forum.list_messages(topic)
    {:ok, _} = Reactions.toggle(user_fixture(), first, "agree")
    next_diff(view)

    {:ok, _} = Reactions.toggle(user_fixture(), first, "heart")
    assert next_diff(view) < 1_000
  end
end

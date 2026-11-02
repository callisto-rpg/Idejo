# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.LiveUpdateSizeTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Reactions
  alias Idejo.Repo

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

  # The entries of the messages an update did not touch are kept as they were, the very same
  # terms, so neither the view nor LiveView's keyed list works them out again (NF-01).
  @tag req: "NF-01"
  test "NF-01 an update makes again only the entry of the message it changed", %{
    topic: topic,
    view: view
  } do
    # Compared in the view's own process: :sys.get_state/1 would copy them.
    in_view = fn fun ->
      me = self()

      :sys.replace_state(view.pid, fn state ->
        send(me, {:in_view, fun.(state.socket.assigns.listed.pairs)})
        state
      end)

      assert_receive {:in_view, result}
      result
    end

    writer = user_fixture()
    {:ok, message} = Messages.commit(writer, topic, "Hello")
    render(view)
    in_view.(&Process.put(:pairs_before, &1))

    {:ok, _} = Messages.commit(writer, topic, "Hello. And more")
    render(view)

    remade =
      in_view.(fn later ->
        before = Process.get(:pairs_before)

        for {id, pair} <- later, not :erts_debug.same(pair, before[id]), do: id
      end)

    assert remade == [message.id]
  end

  # GM-11: the earlier versions of an edited message are rendered once, where it is loaded or
  # broadcast; each viewer rendered every one of them again at each update of the message.
  @tag req: "NF-01"
  test "NF-01 an update of an edited message renders no Markdown in the viewers' views", %{
    topic: topic,
    view: view
  } do
    writer = user_fixture()
    {:ok, message} = Messages.commit(writer, topic, "Hello there")
    # Changing sent text keeps a version (GM-11), three times.
    for text <- ["Hullo there", "Hallo there", "Hello all"],
        do: {:ok, _} = Messages.commit(writer, topic, text)

    render(view)
    :erlang.trace(view.pid, true, [:call])
    :erlang.trace_pattern({Idejo.Markdown, :to_html, :_}, true, [:local])

    {:ok, updated} = Messages.commit(writer, topic, "Hello all. And more")
    assert render(view) =~ "And more"
    assert render(view) =~ "Hullo there"
    assert length(Repo.preload(updated, :versions, force: true).versions) == 3

    :erlang.trace(view.pid, false, [:call])
    refute_received {:trace, _, :call, {Idejo.Markdown, :to_html, _}}
    assert message.id == updated.id
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AP14GrowingMessageTest do
  @moduledoc """
  AP-14: the growing message through the API, against the real engine (`Idejo.Messages`):
  the same invariants and timers as the web composer (GM-01 to GM-16).
  """
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures
  import IdejoWeb.ApiHelpers
  import Phoenix.LiveViewTest

  import Ecto.Query

  alias Idejo.{Forum, Messages, Repo, Settings}
  alias Idejo.Messages.Message

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Chat", "body" => "Hi all"})
    author = user_fixture()
    {token, _row} = api_token_fixture(author)

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, topic: topic, starter: starter, author: author, token: token}
  end

  defp typing(token, topic),
    do:
      build_conn()
      |> api_conn(token)
      |> post(~p"/api/v1/topics/#{topic.id}/composer/typing", %{})
      |> api_json(200)

  defp commit(token, topic, body, opts \\ %{}) do
    build_conn()
    |> api_conn(token)
    |> post(~p"/api/v1/topics/#{topic.id}/composer/commit", Map.merge(%{"body_md" => body}, opts))
  end

  defp enter(token, topic, body), do: commit(token, topic, body) |> api_json(200)

  defp ctrl_enter(token, topic, body),
    do: commit(token, topic, body, %{"break" => true}) |> api_json(200)

  defp composer(token, topic),
    do:
      build_conn()
      |> api_conn(token)
      |> get(~p"/api/v1/topics/#{topic.id}/composer")
      |> api_json(200)

  # As if the window had gone by.
  defp end_window!(id) do
    Repo.get!(Message, id)
    |> Ecto.Changeset.change(closes_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update!()
  end

  # As if the unanswered message time had gone by too.
  defp age!(id, seconds) do
    message = Repo.get!(Message, id)
    past = DateTime.add(DateTime.utc_now(), -seconds, :second)

    message
    |> Ecto.Changeset.change(
      opened_at: past,
      timer_from: past,
      closes_at: DateTime.add(past, 15, :second)
    )
    |> Repo.update!()
  end

  @tag req: "AP-14"
  test "AP-14 typing, then Enter, Enter, Ctrl+Enter inside the window gives one message", %{
    topic: topic,
    token: token,
    author: author
  } do
    typed = typing(token, topic)
    assert typed["typing_since"]

    first = enter(token, topic, "Hello")
    assert first["message"]["state"] == "open"
    assert first["message"]["body_md"] == "Hello."
    assert first["composer"]["open_message_id"] == first["message"]["id"]

    # Invariant 2: closes_at = timer_from + window, timer_from the first keystroke's time.
    stored = Repo.get!(Message, first["message"]["id"])
    {:ok, since, 0} = DateTime.from_iso8601(typed["typing_since"])
    assert DateTime.compare(stored.timer_from, since) == :eq
    assert DateTime.diff(stored.closes_at, stored.timer_from) == 15

    second = enter(token, topic, "Hello. How are you")
    assert second["message"]["id"] == first["message"]["id"]
    assert Repo.get!(Message, stored.id).closes_at == stored.closes_at

    third = ctrl_enter(token, topic, "Hello. How are you. Fine")
    assert third["message"]["id"] == first["message"]["id"]
    assert third["message"]["state"] == "closed"
    assert third["message"]["held"] == true
    assert third["composer"]["held_until"]

    assert Repo.aggregate(from(m in Message, where: m.author_id == ^author.id), :count) == 1
    assert Messages.list_versions(Repo.get!(Message, stored.id)) == []
  end

  @tag req: "AP-14"
  test "AP-14 Ctrl+Enter after the window with someone below, and after the unanswered time with nobody",
       %{topic: topic, token: token, starter: starter} do
    # Someone wrote below: the window alone holds it.
    %{"message" => %{"id" => id}} = enter(token, topic, "One")
    {:ok, _} = Forum.post_message(starter, topic, %{"body" => "Reply below"})
    end_window!(id)
    closed = ctrl_enter(token, topic, "One. Done")
    assert closed["message"]["state"] == "closed"
    refute closed["message"]["held"]
    assert closed["composer"]["held_until"] == nil

    # Nobody below: past the window, Ctrl+Enter still holds until the unanswered time.
    %{"message" => %{"id" => id}} = enter(token, topic, "Two")
    end_window!(id)
    held = ctrl_enter(token, topic, "Two. Alone")
    assert held["message"]["held"] == true

    assert commit(token, topic, "Too early") |> api_json(409) |> get_in(["error", "code"]) ==
             "too_soon"
  end

  @tag req: "AP-14"
  test "AP-14 after the unanswered time a lone author's Ctrl+Enter starts a new message", %{
    topic: topic,
    token: token
  } do
    %{"message" => %{"id" => id}} = enter(token, topic, "Alone")
    age!(id, Messages.unanswered_seconds() + 5)
    done = ctrl_enter(token, topic, "Alone. Done")
    assert done["message"]["state"] == "closed"
    refute done["message"]["held"]
    assert enter(token, topic, "Next")["message"]["id"] != id
  end

  @tag req: "AP-14"
  test "AP-14 held and too_soon, Reply with new: true and the gm_early_reply exception", %{
    admin: admin,
    topic: topic,
    token: token,
    starter: starter
  } do
    {:ok, theirs} = Forum.post_message(starter, topic, %{"body" => "A question"})
    %{"message" => %{"id" => open_id}} = enter(token, topic, "Mine")

    # A new message without a reply while the timers run: refused, nothing changes.
    body = commit(token, topic, "Other", %{"new" => true}) |> api_json(409)
    assert body["error"]["code"] == "too_soon"
    assert body["error"]["message"] =~ "You cannot post a new message yet"
    assert Repo.get!(Message, open_id).state == "open"

    # Reply: a new message at once (gm_early_reply on), the open one closed.
    reply =
      commit(token, topic, "An answer", %{"new" => true, "reply_to" => [theirs.id]})
      |> api_json(200)

    assert reply["message"]["id"] != open_id
    assert [%{"message_id" => quoted}] = reply["message"]["replies_to"]
    assert quoted == theirs.id
    assert Repo.get!(Message, open_id).state == "closed"

    # gm_early_reply off: a reply waits like Ctrl+Enter.
    {:ok, _} = Settings.update_settings(admin, %{"gm_early_reply" => "false"})

    body =
      commit(token, topic, "Another", %{"new" => true, "reply_to" => [theirs.id]})
      |> api_json(409)

    assert body["error"]["code"] == "too_soon"
  end

  @tag req: "AP-14"
  test "AP-14 automatic punctuation follows the author's choice", %{topic: topic, token: token} do
    assert enter(token, topic, "With a dot")["message"]["body_md"] == "With a dot."
    ctrl_enter(token, topic, "With a dot. End")

    me =
      build_conn()
      |> api_conn(token)
      |> patch(~p"/api/v1/me", %{"auto_punctuation" => false})
      |> api_json(200)

    refute me["auto_punctuation"]

    # The held message's timers, as if they had run out.
    Repo.update_all(Message, set: [held: false])
    assert enter(token, topic, "As typed")["message"]["body_md"] == "As typed"
  end

  @tag req: "AP-14"
  test "AP-14 an edit keeps one version however many Enters, Ctrl+Enter ends it", %{
    topic: topic,
    token: token,
    starter: starter
  } do
    id = enter(token, topic, "Original text")["message"]["id"]
    {:ok, _} = Forum.post_message(starter, topic, %{"body" => "Below"})
    end_window!(id)

    Repo.get!(Message, id)
    |> Ecto.Changeset.change(state: "closed", closed_at: DateTime.utc_now())
    |> Repo.update!()

    put = fn body, finish ->
      build_conn()
      |> api_conn(token)
      |> put(~p"/api/v1/messages/#{id}", %{"body_md" => body, "finish" => finish})
      |> api_json(200)
    end

    assert put.("Changed text", false)["edited"]
    put.("Changed text again", false)
    put.("Changed text again, done", true)
    assert length(Messages.list_versions(Repo.get!(Message, id))) == 1

    # A new edit keeps a version again.
    put.("A second edit", true)
    assert length(Messages.list_versions(Repo.get!(Message, id))) == 2
  end

  @tag req: "AP-14"
  test "AP-14 deleting the first message of a topic is refused", %{topic: topic, starter: starter} do
    {token, _row} = api_token_fixture(starter)
    [opening] = Forum.list_messages(topic)

    body =
      build_conn()
      |> api_conn(token)
      |> delete(~p"/api/v1/messages/#{opening.id}")
      |> api_json(409)

    assert body["error"]["code"] == "opening"

    {:ok, own} = Forum.post_message(starter, topic, %{"body" => "Mine"})

    deleted =
      build_conn() |> api_conn(token) |> delete(~p"/api/v1/messages/#{own.id}") |> api_json(200)

    assert deleted["state"] == "deleted"
    assert deleted["deleted_by"] == "author"
    assert deleted["body_md"] == nil
  end

  @tag req: "AP-14"
  test "AP-14 the composer state matches what TopicLive shows", %{
    conn: conn,
    topic: topic,
    token: token,
    author: author
  } do
    %{"message" => %{"id" => _id}} = enter(token, topic, "Timed")
    state = composer(token, topic)
    {:ok, may_start, 0} = DateTime.from_iso8601(state["may_start_new_at"])

    {:ok, _lv, html} =
      conn
      |> log_in_user(author)
      |> live_isolated(IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    [_, data_end] = Regex.run(~r/id="composer-timer"[^>]*data-end="(\d+)"/s, html)
    assert String.to_integer(data_end) == DateTime.to_unix(may_start, :millisecond)
    assert state["window_seconds"] == 15
    assert state["unanswered_seconds"] == Messages.unanswered_seconds()
    assert state["reply_allowed_early"] == true
  end

  @tag req: "AP-14"
  test "AP-14 a web session and the app for one user keep one open message (GM-09)", %{
    conn: conn,
    topic: topic,
    token: token,
    author: author
  } do
    {:ok, lv, _html} =
      conn
      |> log_in_user(author)
      |> live_isolated(IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    lv
    |> element("#composer")
    |> render_hook("commit", %{"body" => "From the web", "break" => false})

    from_app = enter(token, topic, "From the web. And the app")

    open = Repo.all(from m in Message, where: m.author_id == ^author.id and m.state == "open")
    assert [%{id: id}] = open
    assert from_app["message"]["id"] == id
    assert Repo.get!(Message, id).body_md == "From the web. And the app."
  end

  @tag req: "AP-14"
  test "AP-14 a refused commit answers the context's code; text already sent stays", %{
    topic: topic,
    token: token,
    admin: admin
  } do
    %{"message" => %{"id" => id}} = enter(token, topic, "Kept")
    {:ok, _} = Forum.moderate_topic(admin, Forum.get_viewable_topic(admin, topic.id), :lock)

    assert commit(token, topic, "Kept. More") |> api_json(403) |> get_in(["error", "code"]) ==
             "forbidden"

    assert Repo.get!(Message, id).body_md == "Kept."
    assert commit(token, topic, nil) |> api_json(400)
  end
end

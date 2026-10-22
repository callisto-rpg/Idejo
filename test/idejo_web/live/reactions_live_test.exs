# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ReactionsLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Reactions

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Picnic", "body" => "Hi :joy:"})

    [message] = Forum.list_messages(topic)

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{topic: topic, message: message}
  end

  defp open(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  @tag req: "TP-17"
  test "TP-17 the 🙂 offers eight emoji and +; a reaction shows under the message, live", %{
    topic: topic,
    message: message
  } do
    me = user_fixture()
    {:ok, lv, html} = open(log_in_user(build_conn(), me), topic)
    assert html =~ ~s(src="/emoji/1f602.svg")

    assert lv |> element("#message-#{message.id}-react summary") |> has_element?()
    assert has_element?(lv, "#message-#{message.id}-react button[aria-label=':agree:']")
    assert has_element?(lv, "#message-#{message.id}-react button[aria-label='More emoji']")

    lv |> element("#message-#{message.id}-react button[aria-label=':agree:']") |> render_click()
    assert has_element?(lv, "#message-#{message.id}-reactions button[aria-pressed=true]")
    refute has_element?(lv, "#message-#{message.id}-reactions .reaction-count")

    # Someone else's reaction arrives live; the count shows when several chose it.
    {:ok, _} = Reactions.toggle(user_fixture(), message, "agree")
    assert has_element?(lv, "#message-#{message.id}-reactions .reaction-count", "2")

    lv |> element("#message-#{message.id}-reactions button") |> render_click()
    refute has_element?(lv, "#message-#{message.id}-reactions button[aria-pressed=true]")
  end

  @tag req: "TP-17"
  test "TP-17 the + opens every emoji with a search box", %{topic: topic, message: message} do
    {:ok, lv, _html} = open(log_in_user(build_conn(), user_fixture()), topic)

    lv
    |> element("#message-#{message.id}-react button[aria-label='More emoji']")
    |> render_click()

    assert has_element?(lv, "dialog#emoji-picker[aria-labelledby=emoji-picker-title]")
    assert has_element?(lv, "#emoji-picker button[aria-label=':bruh:']")

    lv |> form("#emoji-search-form", %{q: "tada"}) |> render_change()
    refute has_element?(lv, "#emoji-picker button[aria-label=':bruh:']")
    lv |> element("#emoji-picker button[aria-label=':tada:']") |> render_click()

    refute has_element?(lv, "#emoji-picker")
    assert [%{emoji: "tada"}] = Reactions.summary(message.id)
  end

  @tag req: "TP-17"
  test "TP-17 visitors see reactions but cannot react; the images are served", %{
    topic: topic,
    message: message
  } do
    {:ok, _} = Reactions.toggle(user_fixture(), message, "heart")
    {:ok, lv, _html} = open(build_conn(), topic)
    assert has_element?(lv, "#message-#{message.id}-reactions span.reaction[role=img]")
    refute has_element?(lv, "#message-#{message.id}-react")

    assert build_conn() |> get("/emoji/1f602.svg") |> response(200) =~ "<svg"
    assert build_conn() |> get("/reactions/agree.png") |> response(200)
  end
end

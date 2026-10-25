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
  test "TP-17 React offers eight emoji and +; a reaction shows under the message, live", %{
    topic: topic,
    message: message
  } do
    me = user_fixture()
    {:ok, lv, html} = open(log_in_user(build_conn(), me), topic)
    assert html =~ ~s(src="/emoji/1f602.svg?vsn=#{Idejo.Emoji.version()}")

    # A "React" action like Edit or Report (steward decision, 2026-10-25); a click outside
    # closes its choices.
    assert has_element?(lv, "#message-#{message.id}-react summary.message-action", "React")
    assert File.read!("assets/js/account_menu.js") =~ ".add-reaction[open]"
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
  test "TP-17 the + opens the picker; the browser draws it and the choice reacts", %{
    topic: topic,
    message: message
  } do
    {:ok, lv, _html} = open(log_in_user(build_conn(), user_fixture()), topic)

    lv
    |> element("#message-#{message.id}-react button[aria-label='More emoji']")
    |> render_click()

    assert has_element?(lv, "dialog#emoji-picker[aria-labelledby=emoji-picker-title]")
    picker = lv |> element("#emoji-picker-body") |> render()
    assert picker =~ ~s(phx-hook="EmojiPicker")
    assert picker =~ ~s(data-message-id="#{message.id}")
    assert picker =~ ~s(data-src="/emoji-index.json?v=#{Idejo.Emoji.index_version()}")
    assert picker =~ ~s(<input type="search" id="emoji-search")
    # The emoji themselves are not sent over the live connection.
    refute picker =~ "add-reaction-choice"

    lv |> element("#emoji-picker-body") |> render_hook("react", %{id: message.id, emoji: "tada"})
    refute has_element?(lv, "#emoji-picker")
    assert [%{emoji: "tada"}] = Reactions.summary(message.id)
  end

  @tag req: "TP-17"
  test "TP-17 the picker's list: every emoji by category, kept by the browser" do
    conn = get(build_conn(), "/emoji-index.json?v=#{Idejo.Emoji.index_version()}")

    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]

    assert %{"categories" => [%{"key" => "Server", "emoji" => server} | _] = categories} =
             json_response(conn, 200)

    assert ["agree", ":agree:", "/reactions/agree.png" <> _, []] = hd(server)

    all = for %{"emoji" => emoji} <- categories, entry <- emoji, do: entry
    assert length(all) == Enum.sum(for {_, e} <- Idejo.Emoji.groups(), do: length(e))
    assert ["+1", "👍", "/emoji/1f44d.svg" <> _, ["thumbsup"]] = Enum.find(all, &(hd(&1) == "+1"))

    # An old address is checked each time instead.
    assert build_conn() |> get("/emoji-index.json") |> get_resp_header("cache-control") ==
             ["no-cache"]
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

    # Versioned addresses are kept for good: no request when the image is used again.
    conn = get(build_conn(), Idejo.Emoji.lookup("joy").src)
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
  end
end

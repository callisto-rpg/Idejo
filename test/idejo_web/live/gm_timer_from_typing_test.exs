# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.GMTimerFromTypingTest do
  @moduledoc """
  The patience timers start when the author starts typing a message, not at its first send
  (steward request, 2026-11-09): the window (GM-03) and the unanswered message time (GM-05,
  from 0.1 minutes). Not async: it changes server-wide settings.
  """
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Timers", "body" => "Hi"})
    %{admin: admin, author: author, topic: topic}
  end

  @tag req: "GM-03"
  test "GM-03 the window counts from when the author started typing, never before the send", %{
    author: author,
    topic: topic
  } do
    started = DateTime.add(DateTime.utc_now(), -10, :second)
    {:ok, message} = Messages.commit(author, topic, "Hello", started_at: started)

    assert message.timer_from == started
    assert_in_delta DateTime.diff(message.closes_at, started), 15, 1
    assert Messages.timer_start(message) == started

    # Typing for longer than the window: it has ended at the first send.
    {:ok, slow} =
      Messages.commit(user_fixture(), topic, "Slow",
        started_at: DateTime.add(DateTime.utc_now(), -60)
      )

    assert DateTime.compare(slow.closes_at, slow.opened_at) == :eq
    assert Messages.window_ended?(slow)

    # A time from the future counts as now.
    {:ok, later} =
      Messages.commit(user_fixture(), topic, "Later",
        started_at: DateTime.add(DateTime.utc_now(), 3600)
      )

    assert DateTime.compare(later.timer_from, DateTime.utc_now()) != :gt
  end

  @tag req: "GM-05"
  test "GM-05 the unanswered message time takes decimals, from 0.1 minutes, from typing", %{
    admin: admin,
    author: author,
    topic: topic
  } do
    {:ok, _} = Settings.update_settings(admin, %{"gm_unanswered_minutes" => "0.1"})
    {:ok, _} = Settings.update_settings(admin, %{"gm_window_seconds" => "0"})
    assert Messages.unanswered_seconds() == 6

    started = DateTime.add(DateTime.utc_now(), -7, :second)
    {:ok, message} = Messages.commit(author, topic, "Alone", started_at: started)

    assert DateTime.compare(Messages.unanswered_until(message), DateTime.utc_now()) == :lt
    assert Messages.may_start_new?(message)

    assert {:error, _} = Settings.update_settings(admin, %{"gm_unanswered_minutes" => "0.05"})
  end

  @tag req: "GM-03"
  test "GM-03 the composer's line runs from the first keystroke, and the send keeps that time",
       %{conn: conn, author: author, topic: topic} do
    {:ok, view, _html} =
      live_isolated(log_in_user(conn, author), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    refute has_element?(view, "#composer-timer")

    before = DateTime.utc_now()
    render_hook(view, "composer_typing", %{"typing" => true})
    assert has_element?(view, "#composer-timer")

    [start] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#composer-timer")
      |> LazyHTML.attribute("data-start")

    assert_in_delta String.to_integer(start), DateTime.to_unix(before, :millisecond), 1000

    # Emptied before sending: no line, and a new start next time.
    render_hook(view, "composer_typing", %{"typing" => false})
    refute has_element?(view, "#composer-timer")

    render_hook(view, "composer_typing", %{"typing" => true})
    typed_at = DateTime.utc_now()
    render_hook(view, "commit", %{"body" => "First line", "break" => false})

    message = Messages.open_message(author, topic)

    assert_in_delta DateTime.to_unix(message.timer_from, :millisecond),
                    DateTime.to_unix(typed_at, :millisecond),
                    1000

    assert DateTime.compare(message.timer_from, message.opened_at) != :gt
  end
end

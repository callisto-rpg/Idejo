# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicNavTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Reading
  alias Idejo.Repo

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Picnic", "body" => "Saturday?"})

    reader =
      user_fixture()
      |> Ecto.Changeset.change(created_at: DateTime.add(DateTime.utc_now(:second), -3600))
      |> Repo.update!()

    %{conn: log_in_user(conn, reader), reader: reader, topic: topic}
  end

  defp post!(topic, user \\ user_fixture(), body \\ "Count me in") do
    {:ok, message} = Forum.post_message(user, topic, %{"body" => body})
    message
  end

  defp page(conn, topic), do: get(conn, ~p"/t/#{topic.id}/#{topic.slug}")

  @tag req: "TP-07"
  test "TP-07 back in a topic, a line marks the oldest unread message, until it fades", %{
    conn: conn,
    reader: reader,
    topic: topic
  } do
    # The first visit has nothing to go back to.
    refute conn |> page(topic) |> html_response(200) =~ ~s(id="unread-line")

    first = post!(topic)
    post!(topic)
    post!(topic, reader, "Mine")
    html = conn |> page(topic) |> html_response(200) |> LazyHTML.from_document()

    assert html |> LazyHTML.query("#message-#{first.id} > #unread-line") |> LazyHTML.text() =~
             "2 unread messages"

    assert html
           |> LazyHTML.query(~s(#topic-nav-unread[href="#message-#{first.id}"]))
           |> Enum.any?()

    # Connected, as the page's embedded view gets it from the controller.
    {:ok, lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id, "first_unread" => %{id: first.id, count: 2}}
      )

    assert has_element?(lv, "#message-#{first.id} > #unread-line", "2 unread messages")

    # Faded: the line goes, the navigator still leads there.
    render_hook(lv, "unread_line_done", %{})
    refute has_element?(lv, "#unread-line")
    assert has_element?(lv, "#topic-nav-unread")

    # The page marked everything read, so the next visit has no line.
    assert Reading.first_unread(reader, topic) == nil
    refute conn |> recycle() |> page(topic) |> html_response(200) =~ ~s(id="unread-line")
  end

  @tag req: "TP-07"
  test "TP-07 the topic navigator links to the first, last and the reader's last message", %{
    conn: conn,
    reader: reader,
    topic: topic
  } do
    [opening] = Forum.list_messages(topic)
    {:ok, lv, _html} = live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})
    assert has_element?(lv, "nav#topic-nav[aria-label='Topic navigation']")
    assert has_element?(lv, ~s(#topic-nav-first[href="#message-#{opening.id}"]))
    assert has_element?(lv, ~s(#topic-nav-last[href="#message-#{opening.id}"]))
    refute has_element?(lv, "#topic-nav-mine")
    refute has_element?(lv, "#topic-nav-unread")

    mine = post!(topic, reader, "Mine")
    last = post!(topic)
    assert has_element?(lv, ~s(#topic-nav-mine[href="#message-#{mine.id}"]))
    assert has_element?(lv, ~s(#topic-nav-last[href="#message-#{last.id}"]))

    # Visitors get the navigator without "My last message".
    {:ok, lv, _html} =
      live_isolated(build_conn(), IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    assert has_element?(lv, "#topic-nav-first")
    refute has_element?(lv, "#topic-nav-mine")
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UnreadTest do
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
      user_fixture(%{display_name: "Rae"})
      |> Ecto.Changeset.change(created_at: DateTime.add(DateTime.utc_now(:second), -3600))
      |> Repo.update!()

    %{conn: log_in_user(conn, reader), reader: reader, topic: topic}
  end

  defp post!(topic, body \\ "Count me in") do
    {:ok, message} = Forum.post_message(user_fixture(), topic, %{"body" => body})
    message
  end

  defp marker(html, topic) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#topic-#{topic.id} .unread-marker")
    |> LazyHTML.text()
    |> String.trim()
  end

  @tag req: "TP-03"
  test "TP-03 the topic list shows the signed-in user's unread marker", %{
    conn: conn,
    reader: reader,
    topic: topic
  } do
    Reading.mark_read(reader, topic)
    assert conn |> get(~p"/c/general") |> html_response(200) |> marker(topic) == ""

    post!(topic)
    post!(topic)
    assert conn |> get(~p"/c/general") |> html_response(200) |> marker(topic) == "2 new"

    # Visitors have no read positions, so no marker.
    assert build_conn() |> get(~p"/c/general") |> html_response(200) |> marker(topic) == ""
  end

  @tag req: "TP-07"
  test "TP-07 Unread lists followed topics first, under Following, then the others", %{
    conn: conn,
    reader: reader,
    topic: topic
  } do
    {:ok, followed} =
      Forum.create_topic(user_fixture(), Repo.preload(topic, :category).category, %{
        "title" => "Bikes",
        "body" => "Hi"
      })

    :ok = Reading.follow(reader, followed)
    post!(followed)
    post!(topic)

    doc = conn |> get(~p"/unread") |> html_response(200) |> LazyHTML.from_document()
    titles = &(doc |> LazyHTML.query(&1) |> Enum.map(fn li -> LazyHTML.text(li) end))

    assert doc |> LazyHTML.query("#unread-following") |> LazyHTML.text() == "Following"
    assert doc |> LazyHTML.query("#unread-others") |> LazyHTML.text() =~ "Other topics"
    assert titles.("#followed-topics li > a") == ["Bikes"]
    assert titles.("#topics li > a") == ["Picnic"]
    assert marker(LazyHTML.to_html(doc), followed) == "2 new"

    # Unfollowed, it goes back among the others; without any followed, no headings.
    :ok = Reading.unfollow(reader, followed)
    html = conn |> get(~p"/unread") |> html_response(200)
    refute html =~ "followed-topics"
    refute html =~ "unread-others"
    assert html =~ "Bikes"
  end

  @tag req: "TP-07"
  test "TP-07 opening a topic marks it read and it leaves Unread", %{conn: conn, topic: topic} do
    home = conn |> get(~p"/") |> html_response(200)
    assert home =~ ~s(id="unread-link")

    unread = conn |> get(~p"/unread") |> html_response(200)
    assert marker(unread, topic) == "1 new"
    assert unread =~ "Picnic"

    conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)

    unread = conn |> get(~p"/unread") |> html_response(200)
    assert unread =~ "Nothing new since your last visit."
    refute unread =~ "Picnic"
    assert conn |> get(~p"/c/general") |> html_response(200) |> marker(topic) == ""
  end

  @tag req: "TP-07"
  test "TP-07 messages arriving while the topic is open count as read", %{
    conn: conn,
    reader: reader,
    topic: topic
  } do
    {:ok, lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    assert Reading.unread_counts(reader, [topic.id]) == %{}

    message = post!(topic, "Live one")
    assert has_element?(lv, "#message-#{message.id}", "Live one")
    assert Reading.unread_counts(reader, [topic.id]) == %{}

    # Gone from the topic, the next message is new again.
    GenServer.stop(lv.pid)
    post!(topic, "Later one")
    assert Reading.unread_counts(reader, [topic.id]) == %{topic.id => 1}
  end

  @tag req: "TP-07"
  test "TP-07 Unread needs a signed-in user" do
    conn = build_conn() |> get(~p"/unread")
    assert redirected_to(conn) == ~p"/users/sign-in"
    refute build_conn() |> get(~p"/") |> html_response(200) =~ ~s(id="unread-link")
  end
end

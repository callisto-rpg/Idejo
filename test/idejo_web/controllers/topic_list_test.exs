# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicListTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    %{general: general, starter: user_fixture(%{display_name: "Sam Starter"})}
  end

  defp topic!(user, category, title, last_activity_at) do
    {:ok, topic} = Forum.create_topic(user, category, %{"title" => title, "body" => "Hi"})

    topic
    |> Ecto.Changeset.change(last_activity_at: last_activity_at)
    |> Repo.update!()
  end

  defp at(minutes_ago), do: DateTime.add(DateTime.utc_now(), -minutes_ago * 60)

  defp titles(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#topics li > a")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  @tag req: "TP-03"
  test "TP-03 the category lists its topics with title, starter, messages and last activity",
       %{conn: conn, general: general, starter: starter} do
    topic = topic!(starter, general, "Hello there", at(5))
    html = conn |> get(~p"/c/general") |> html_response(200)

    assert html =~ ~s(href="/t/#{topic.id}/hello-there")
    assert html =~ "Hello there"
    assert html =~ "Sam Starter"
    assert html =~ "1 message"
    assert html =~ ~s(datetime="#{DateTime.to_iso8601(topic.last_activity_at)}")
    refute html =~ "No topics yet."
  end

  @tag req: "TP-03"
  test "TP-03 pinned topics come first, then the most recently active", %{
    conn: conn,
    general: general,
    starter: starter
  } do
    topic!(starter, general, "Old", at(60))
    topic!(starter, general, "Newest", at(1))
    pinned = topic!(starter, general, "Rules", at(600))
    pinned |> Ecto.Changeset.change(pinned: true) |> Repo.update!()

    html = conn |> get(~p"/c/general") |> html_response(200)
    assert titles(html) == ["Rules", "Newest", "Old"]
    assert html =~ "Pinned"
  end

  @tag req: "TP-03"
  test "TP-03 only the category's own topics are listed", %{
    conn: conn,
    general: general,
    starter: starter
  } do
    {:ok, other} =
      Forum.create_category(user_with_role_fixture(:administrator), %{"name" => "Other"})

    topic!(starter, general, "Here", at(1))
    topic!(starter, other, "Elsewhere", at(1))

    assert titles(conn |> get(~p"/c/general") |> html_response(200)) == ["Here"]
  end

  @tag req: "TP-03"
  test "TP-03 long lists are paged, without JavaScript", %{
    conn: conn,
    general: general,
    starter: starter
  } do
    for n <- 1..31, do: topic!(starter, general, "Topic #{n}", at(n))

    first = conn |> get(~p"/c/general") |> html_response(200)
    assert length(titles(first)) == 30
    assert first =~ ~s(href="/c/general?page=2")
    refute first =~ "Previous page"

    second = conn |> get(~p"/c/general?page=2") |> html_response(200)
    assert titles(second) == ["Topic 31"]
    assert second =~ ~s(href="/c/general?page=1")
    refute second =~ "Next page"

    assert titles(conn |> get(~p"/c/general?page=nope") |> html_response(200)) ==
             titles(first)
  end

  @tag req: "TP-03"
  test "TP-03 an empty category says so", %{conn: conn} do
    assert conn |> get(~p"/c/general") |> html_response(200) =~ "No topics yet."
    refute Repo.exists?(Topic)
  end
end

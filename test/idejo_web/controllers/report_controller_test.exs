# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ReportControllerTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Moderation

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture(%{display_name: "Ada"})

    {:ok, topic} =
      Forum.create_topic(author, general, %{"title" => "Plans", "body" => "Rude words"})

    [message] = Forum.list_messages(topic)
    %{author: author, topic: topic, message: message}
  end

  @tag req: "MO-01"
  test "MO-01 a member reports from the topic, without JavaScript", %{
    author: author,
    topic: topic,
    message: message
  } do
    reporter = log_in_user(build_conn(), user_fixture(%{display_name: "Rae"}))

    {:ok, lv, _html} =
      live_isolated(reporter, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    assert has_element?(lv, ~s(#message-#{message.id}-report[href="/m/#{message.id}/report"]))

    {:ok, own, _html} =
      live_isolated(log_in_user(build_conn(), author), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    refute has_element?(own, "#message-#{message.id}-report")

    {:ok, visitor, _html} =
      live_isolated(build_conn(), IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    refute has_element?(visitor, "#message-#{message.id}-report")

    page = reporter |> get(~p"/m/#{message.id}/report") |> html_response(200)
    assert page =~ "Ada in “Plans”"

    conn = post(reporter, ~p"/m/#{message.id}/report", %{"report" => %{"reason" => ""}})
    assert html_response(conn, 200) =~ "can&#39;t be blank"

    conn = post(reporter, ~p"/m/#{message.id}/report", %{"report" => %{"reason" => "Insults"}})
    assert redirected_to(conn) == ~p"/m/#{message.id}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "The moderators will look at it."

    assert_error_sent 404, fn ->
      get(log_in_user(build_conn(), author), ~p"/m/#{message.id}/report")
    end

    assert redirected_to(get(build_conn(), ~p"/m/#{message.id}/report")) == ~p"/users/sign-in"
  end

  @tag req: "MO-01"
  test "MO-01 moderators see the queue and resolve reports", %{message: message} do
    {:ok, _} =
      Moderation.report_message(user_fixture(%{display_name: "Rae"}), message, %{
        "reason" => "Insults <b>"
      })

    moderator = log_in_user(build_conn(), user_with_role_fixture(:moderator))

    home = moderator |> get(~p"/") |> html_response(200)

    assert home
           |> LazyHTML.from_document()
           |> LazyHTML.query("#moderation-link .badge")
           |> LazyHTML.text() =~ "1"

    queue = moderator |> get(~p"/moderation") |> html_response(200)
    assert queue =~ "Rae"
    assert queue =~ "Insults &lt;b&gt;"
    assert queue =~ ~s(id="handle-#{message.id}")

    conn =
      post(moderator, ~p"/moderation/reports/#{message.id}", %{
        "outcome" => "resolve",
        "note" => "Edited"
      })

    assert redirected_to(conn) == ~p"/moderation"
    assert moderator |> get(~p"/moderation") |> html_response(200) =~ "No open reports."

    assert moderator |> get(~p"/moderation/log") |> html_response(200) =~
             "Resolved reports about a message"

    assert_error_sent 404, fn ->
      get(log_in_user(build_conn(), user_fixture()), ~p"/moderation")
    end
  end
end

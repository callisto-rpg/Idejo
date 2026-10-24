# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InlineRepliesTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Repo

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture(%{display_name: "Sam Starter"})

    {:ok, topic} =
      Forum.create_topic(starter, general, %{"title" => "Plans", "body" => "What *next*?"})

    [first] = Forum.list_messages(topic)
    member = user_fixture(%{display_name: "Mia Member"})

    %{
      conn: log_in_user(conn, member),
      admin: admin,
      topic: topic,
      first: first,
      member: member
    }
  end

  defp page(topic), do: ~p"/t/#{topic.id}/plans"

  # The list and the form are a LiveView embedded in the server-rendered page, with this
  # session.
  defp form_live(conn, topic, reply_to \\ nil) do
    live_isolated(conn, IdejoWeb.TopicLive,
      session: %{"topic_id" => topic.id, "reply_to_id" => reply_to && reply_to.id}
    )
  end

  # What the Composer hook sends on Enter.
  defp enter(lv, body), do: lv |> element("#composer") |> render_hook("commit", %{"body" => body})

  @tag req: "TP-08"
  test "TP-08 members get the composer and a Reply link on each message", %{
    conn: conn,
    topic: topic,
    first: first
  } do
    html = conn |> get(page(topic)) |> html_response(200)
    assert html =~ ~s(id="composer")
    assert html =~ ~s(href="/t/#{topic.id}/plans?reply_to=#{first.id}#composer")

    visitor = build_conn() |> get(page(topic)) |> html_response(200)
    refute visitor =~ ~s(id="composer")
    refute visitor =~ "reply_to="
    assert visitor =~ "Sign in to take part."
  end

  @tag req: "TP-08"
  test "TP-08 a member replies to a message and the reply shows an excerpt linking to it", %{
    conn: conn,
    topic: topic,
    first: first
  } do
    # The Reply link opens the page with the form replying to that message.
    assert conn |> get(page(topic) <> "?reply_to=#{first.id}") |> html_response(200) =~
             "Replying to Sam Starter:"

    {:ok, lv, _html} = form_live(conn, topic, first)
    assert lv |> element("#replying-to") |> render() =~ "What next?"

    enter(lv, "Lunch **first**")

    [_, reply] = Forum.list_messages(topic)
    assert reply.reply_to_id == first.id
    refute has_element?(lv, "#replying-to")
    {:ok, _} = Idejo.Messages.close(reply)

    # Others see it at once, quoting what it replies to.
    assert has_element?(lv, "#message-#{reply.id}-reply-to", "In reply to Sam Starter")

    html = conn |> get(page(topic)) |> html_response(200)

    quote_html =
      html |> LazyHTML.from_document() |> LazyHTML.query("#message-#{reply.id}-reply-to")

    assert LazyHTML.text(quote_html) =~ "In reply to Sam Starter"
    assert LazyHTML.text(quote_html) =~ "What next?"
    assert LazyHTML.attribute(LazyHTML.query(quote_html, "a"), "href") == ["/m/#{first.id}"]
    assert html =~ "<strong>first</strong>"
  end

  @tag req: "TP-08"
  test "TP-08 a plain message, and a reply can be cancelled", %{
    conn: conn,
    topic: topic,
    first: first
  } do
    {:ok, lv, _html} = form_live(conn, topic, first)
    lv |> element("#replying-to button", "Cancel reply") |> render_click()
    refute has_element?(lv, "#replying-to")

    enter(lv, "Just saying")
    [_, message] = Forum.list_messages(topic)
    assert message.reply_to_id == nil
    assert message.body_md == "Just saying."
  end

  @tag req: "TP-08"
  test "TP-08 an empty message is not posted", %{conn: conn, topic: topic} do
    {:ok, lv, _html} = form_live(conn, topic)
    enter(lv, "   ")
    assert length(Forum.list_messages(topic)) == 1
  end

  @tag req: "TP-08"
  test "TP-08 a locked topic shows no form", %{conn: conn, topic: topic} do
    topic |> Ecto.Changeset.change(state: "locked") |> Repo.update!()
    html = conn |> get(page(topic)) |> html_response(200)

    refute html =~ ~s(id="composer")
    refute html =~ "reply_to="
    assert html =~ "This topic takes no new messages."
  end

  @tag req: "TP-08"
  test "TP-08 the topic page still reads without JavaScript", %{
    topic: topic,
    first: first,
    member: member
  } do
    {:ok, _} = Forum.post_message(member, topic, %{"body" => "Hi", "reply_to_id" => first.id})
    html = build_conn() |> get(page(topic)) |> html_response(200)

    refute html =~ "data-phx-main"
    assert html =~ "In reply to Sam Starter"
  end

  # Steward decision, 2026-10-24: Reply starts a new message, not an append.
  @tag req: "TP-08"
  test "TP-08 Reply with a message still open starts a new message", %{
    conn: conn,
    topic: topic,
    first: first,
    member: member
  } do
    {:ok, open} = Idejo.Messages.commit(member, topic, "Still talking")

    {:ok, lv, _html} = form_live(conn, topic, first)
    # The open message reads like the others; the composer is a new one at the end.
    assert has_element?(lv, "#message-#{open.id} .message-body", "Still talking.")
    assert has_element?(lv, "#composer-slot #composer")
    refute has_element?(lv, "#composer[data-sent]")

    enter(lv, "About that")

    [_, closed, reply] = Forum.list_messages(topic)
    assert closed.id == open.id
    assert closed.state == "closed"
    assert closed.body_md == "Still talking."
    assert reply.reply_to_id == first.id
    assert reply.body_md == "About that."
    assert reply.state == "open"
    assert has_element?(lv, "#message-#{reply.id} #composer")
  end

  @tag req: "TP-08"
  test "TP-08 removing the reply before the timer ends refuses Enter with a dialog", %{
    conn: conn,
    topic: topic,
    first: first,
    member: member
  } do
    {:ok, open} = Idejo.Messages.commit(member, topic, "Still talking")
    {:ok, lv, _html} = form_live(conn, topic, first)

    lv |> element("#replying-to button", "Cancel reply") |> render_click()
    # Still a new message, waiting on the open one's timer.
    assert has_element?(lv, "#composer-slot #composer")
    assert has_element?(lv, "#composer-timer")

    assert lv |> element("#composer") |> render_hook("commit", %{"body" => "Other thing"}) =~
             "You cannot post a new message yet. Append your old message."

    assert has_element?(lv, "#too-soon-dialog")
    assert [_, %{id: id, state: "open"}] = Forum.list_messages(topic)
    assert id == open.id

    # "Append to my message": the composer is the open message again.
    lv |> element("#too-soon-append") |> render_click()
    refute has_element?(lv, "#too-soon-dialog")
    assert_push_event(lv, "composer_sent", %{body: "Still talking."})
    assert has_element?(lv, "#message-#{open.id} #composer")

    enter(lv, "Still talking. More")
    assert [_, %{id: ^id, body_md: "Still talking. More."}] = Forum.list_messages(topic)
  end
end

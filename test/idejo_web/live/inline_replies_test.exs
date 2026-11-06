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
    # The quote stays over the open message while the author goes on typing; sent, the
    # reply can no longer be cancelled.
    assert has_element?(lv, "#replying-to", "Replying to Sam Starter:")
    refute has_element?(lv, "#replying-to button", "Cancel reply")
    enter(lv, "Lunch **first**. Then plans")
    assert has_element?(lv, "#replying-to", "What next?")

    {:ok, _} = Idejo.Messages.close(Repo.reload!(reply))
    refute has_element?(lv, "#replying-to")

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
  test "TP-08 connected, Reply shows the quote over the composer at once", %{
    conn: conn,
    topic: topic,
    first: first,
    member: member
  } do
    {:ok, lv, _html} = form_live(conn, topic)
    refute has_element?(lv, "#replying-to")

    lv |> element("#message-#{first.id}-reply") |> render_click()
    assert has_element?(lv, "#replying-to", "Replying to Sam Starter:")
    assert_push_event(lv, "composer_focus", %{})

    enter(lv, "About that")
    assert [_, %{reply_to_id: reply_to_id}] = Forum.list_messages(topic)
    assert reply_to_id == first.id
    assert has_element?(lv, "#replying-to", "Replying to Sam Starter:")

    assert [_, %{author_id: author_id}] = Forum.list_messages(topic)
    assert author_id == member.id
  end

  @tag req: "TP-08"
  test "TP-08 an inline reply's quote shows its words as written and links nobody they name", %{
    first: first,
    member: member
  } do
    first = %{first | author: %{member | display_name: "Mia [the] *best*"}}
    first = %{first | body_html: "<p>ask @mia_x +moderator ==now== `x` &amp; ||y||</p>"}
    quote = IdejoWeb.InlineReplies.markdown(first)

    assert quote ==
             "> [Replying to Mia \\[the\\] \\*best\\*:](/m/#{first.id})\n" <>
               "> [ask @mia\\_x +moderator \\=\\=now\\=\\= \\`x\\` \\& \\|\\|y\\|\\|](/m/#{first.id})"

    assert Idejo.Markdown.quoted_messages(quote <> "\n\nYes") == [first.id]
    assert Idejo.Markdown.references(quote) == []

    html = Idejo.Markdown.to_html(quote)
    assert html =~ "Replying to Mia [the] *best*:"
    assert html =~ "ask @mia_x +moderator ==now== `x` &amp; ||y||"
  end

  @tag req: "TP-08"
  test "TP-08 Reply on a message above the open one quotes it inside that message", %{
    conn: conn,
    topic: topic,
    first: first,
    member: member
  } do
    {:ok, open} = Idejo.Messages.commit(member, topic, "Still talking")
    {:ok, lv, _html} = form_live(conn, topic)
    assert has_element?(lv, "#message-#{open.id} #composer")

    lv |> element("#message-#{first.id}-reply") |> render_click()

    # The quote goes into the open message, where the author writes; no new message.
    quote = IdejoWeb.InlineReplies.markdown(Repo.preload(first, :author))
    assert_push_event(lv, "composer_quote", %{markdown: ^quote})
    assert_push_event(lv, "composer_focus", %{})
    refute_push_event(lv, "composer_flush", %{})
    refute has_element?(lv, "#replying-to")
    assert has_element?(lv, "#message-#{open.id} #composer")

    # Several quotes in one message, each answered.
    enter(lv, "Still talking.\n\n#{quote}\n\nYes\n\n#{quote}\n\nAnd no")

    assert [_, %{id: id, state: "open", body_md: body, body_html: html}] =
             Forum.list_messages(topic)

    assert id == open.id
    assert length(String.split(body, "> [Replying to Sam Starter:]")) == 3
    assert length(String.split(html, "<blockquote>")) == 3
    assert html =~ ~s(<a href="/m/#{first.id}")
  end

  @tag req: "TP-08"
  test "TP-08 Reply on a message below the open one sends it and starts a blank reply", %{
    conn: conn,
    topic: topic,
    member: member
  } do
    {:ok, open} = Idejo.Messages.commit(member, topic, "Still talking")
    other = user_fixture(%{display_name: "Olga Other"})
    {:ok, below} = Idejo.Messages.commit(other, topic, "An answer")
    {:ok, lv, _html} = form_live(conn, topic)

    # First what is not sent joins the open message (the hook sends it, then comes back).
    lv |> element("#message-#{below.id}-reply") |> render_click()
    assert_push_event(lv, "composer_flush", %{id: below_id})
    assert below_id == below.id
    refute has_element?(lv, "#replying-to")

    enter(lv, "Still talking. One more thing")
    lv |> element("#composer") |> render_hook("reply", %{"id" => below.id, "flushed" => true})

    # Then a new message at the end, blank, replying.
    assert_push_event(lv, "composer_sent", %{body: "", clear: true})
    assert has_element?(lv, "#replying-to", "Replying to Olga Other:")
    assert has_element?(lv, "#composer-slot #composer")

    enter(lv, "About that")

    assert [_, closed, _below, reply] = Forum.list_messages(topic)
    assert closed.id == open.id
    assert closed.state == "closed"
    assert closed.body_md == "Still talking. One more thing."
    assert reply.reply_to_id == below.id
    assert reply.body_md == "About that."
  end

  @tag req: "TP-08"
  test "TP-08 a second Reply below never carries the sent message into a new one", %{
    conn: conn,
    topic: topic,
    first: first,
    member: member
  } do
    other = user_fixture(%{display_name: "Olga Other"})
    {:ok, lv, _html} = form_live(conn, topic)

    # A reply, sent: open.
    lv |> element("#message-#{first.id}-reply") |> render_click()
    enter(lv, "About that")
    {:ok, below} = Idejo.Messages.commit(other, topic, "An answer")

    # Reply below it: the composer is cleared for the new message, whatever it held.
    lv |> element("#message-#{below.id}-reply") |> render_click()
    assert_push_event(lv, "composer_flush", %{})
    lv |> element("#composer") |> render_hook("reply", %{"id" => below.id, "flushed" => true})
    assert_push_event(lv, "composer_sent", %{body: "", clear: true})

    enter(lv, "Second")

    assert [_, %{body_md: "About that."}, _below, %{body_md: "Second.", author_id: author_id}] =
             Forum.list_messages(topic)

    assert author_id == member.id
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

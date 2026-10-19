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

  # The form is a LiveView embedded in the server-rendered page, with this session.
  defp form_live(conn, topic, reply_to \\ nil) do
    live_isolated(conn, IdejoWeb.MessageFormLive,
      session: %{"topic_id" => topic.id, "reply_to_id" => reply_to && reply_to.id}
    )
  end

  @tag req: "TP-08"
  test "TP-08 members get a message form and a Reply link on each message", %{
    conn: conn,
    topic: topic,
    first: first
  } do
    html = conn |> get(page(topic)) |> html_response(200)
    assert html =~ ~s(id="message-form-section")
    assert html =~ ~s(href="/t/#{topic.id}/plans?reply_to=#{first.id}#message-form-section")

    visitor = build_conn() |> get(page(topic)) |> html_response(200)
    refute visitor =~ "message-form-section"
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

    {:error, {:redirect, %{to: to}}} =
      lv |> form("#message-form", message: %{body: "Lunch **first**"}) |> render_submit()

    [_, reply] = Forum.list_messages(topic)
    assert reply.reply_to_id == first.id
    assert to == page(topic) <> "#message-#{reply.id}"

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

    lv |> form("#message-form", message: %{body: "Just saying"}) |> render_submit()
    [_, message] = Forum.list_messages(topic)
    assert message.reply_to_id == nil
    assert message.body_md == "Just saying"
  end

  @tag req: "TP-08"
  test "TP-08 an empty message is not posted", %{conn: conn, topic: topic} do
    {:ok, lv, _html} = form_live(conn, topic)

    assert lv |> form("#message-form", message: %{body: ""}) |> render_submit() =~
             "can&#39;t be blank"

    assert length(Forum.list_messages(topic)) == 1
  end

  @tag req: "TP-08"
  test "TP-08 a locked topic shows no form", %{conn: conn, topic: topic} do
    topic |> Ecto.Changeset.change(state: "locked") |> Repo.update!()
    html = conn |> get(page(topic)) |> html_response(200)

    refute html =~ "message-form-section"
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
end

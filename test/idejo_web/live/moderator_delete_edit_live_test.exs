# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ModeratorDeleteEditLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture(%{display_name: "Ada"})
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Plans", "body" => "Hello"})
    moderator = user_with_role_fixture(:moderator)
    %{topic: topic, author: author, moderator: moderator}
  end

  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  @tag req: "MO-02"
  test "MO-02 readers see one line for deleted messages in a row; moderators see the text", %{
    topic: topic,
    author: author,
    moderator: moderator
  } do
    {:ok, a} = Forum.post_message(author, topic, %{"body" => "Secret one"})
    {:ok, b} = Forum.post_message(author, topic, %{"body" => "Secret two"})
    {:ok, c} = Forum.post_message(author, topic, %{"body" => "Kept"})
    {:ok, d} = Forum.post_message(author, topic, %{"body" => "Secret three"})
    for m <- [a, b, d], do: {:ok, _} = Messages.delete_as_moderator(moderator, m)

    page = build_conn() |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)
    refute page =~ "Secret"
    assert page =~ "Kept"
    assert page =~ "2 messages deleted by a moderator"
    assert page =~ "Message deleted by a moderator"
    # Permalinks still find their place.
    for m <- [a, b, d], do: assert(page =~ ~s(id="message-#{m.id}"))

    {:ok, reader, _html} = watch(build_conn(), topic)
    assert has_element?(reader, "#message-#{a.id}-deleted", "2 messages deleted by a moderator")
    assert has_element?(reader, "#message-#{b.id}[hidden]")
    assert has_element?(reader, "#message-#{d.id}-deleted", "Message deleted by a moderator")
    refute has_element?(reader, "#message-#{c.id}[hidden]")

    {:ok, mod_view, _html} = watch(log_in_user(build_conn(), moderator), topic)
    assert has_element?(mod_view, "#message-#{a.id}", "Secret one")
    assert has_element?(mod_view, "#message-#{a.id}-deleted.badge", "Deleted by a moderator")
    refute has_element?(mod_view, "#message-#{a.id}-moderate")
  end

  @tag req: "MO-06"
  test "MO-06 moderators see every earlier version of an edited message, even deleted", %{
    topic: topic,
    author: author,
    moderator: moderator
  } do
    {:ok, message} = Forum.post_message(author, topic, %{"body" => "Draft one"})
    {:ok, message} = Messages.edit(author, message, "Draft two")
    {:ok, message} = Messages.edit(author, message, "Final words")

    {:ok, mod_view, _html} = watch(log_in_user(build_conn(), moderator), topic)
    versions = mod_view |> element("#message-#{message.id}-versions") |> render()
    assert versions =~ "Draft one"
    assert versions =~ "Draft two"

    {:ok, _} = Messages.delete_as_moderator(moderator, message, "Spam")
    {:ok, mod_view, _html} = watch(log_in_user(build_conn(), moderator), topic)
    assert has_element?(mod_view, "#message-#{message.id}", "Final words")
    versions = mod_view |> element("#message-#{message.id}-versions") |> render()
    assert versions =~ "Draft one"
    assert versions =~ "Draft two"

    {:ok, reader, _html} = watch(build_conn(), topic)
    refute has_element?(reader, "#message-#{message.id}-versions")
    refute render(reader) =~ "Draft"
  end

  @tag req: "MO-02"
  test "MO-02 a moderator deletes and edits from the topic, with a reason", %{
    topic: topic,
    author: author,
    moderator: moderator
  } do
    {:ok, rude} = Forum.post_message(author, topic, %{"body" => "Rude words"})
    {:ok, typo} = Forum.post_message(author, topic, %{"body" => "Phone 555-0100"})
    {:ok, reader, _html} = watch(build_conn(), topic)
    {:ok, lv, _html} = watch(log_in_user(build_conn(), moderator), topic)

    refute has_element?(reader, "#message-#{rude.id}-moderate")

    lv
    |> form("#message-#{rude.id}-moderate-form", %{"reason" => "Insults"})
    |> render_submit(%{"do" => "delete"})

    assert has_element?(reader, "#message-#{rude.id}-deleted", "Message deleted by a moderator")

    lv |> element("#message-#{typo.id} button", "Edit") |> render_click()
    assert has_element?(lv, "#edit-message-#{typo.id}", "Edit this message (Markdown)")

    lv
    |> form("#edit-message-#{typo.id}", edit: %{body: "Phone [removed]", reason: "Personal data"})
    |> render_submit()

    assert has_element?(reader, "#message-#{typo.id}", "Phone [removed]")
    log = log_in_user(build_conn(), moderator) |> get(~p"/moderation/log") |> html_response(200)
    assert log =~ "Deleted a message"
    assert log =~ "Edited a message"
    assert log =~ "Personal data"
  end
end

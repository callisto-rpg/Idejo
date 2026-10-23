# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.DeleteOwnMessageTest do
  @moduledoc """
  An author deletes their own message by emptying it in the editor (steward decision,
  2026-10-23): asked first, then shown as "Message deleted by user".
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Moderation.Action
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture(%{display_name: "Ada"})

    {:ok, topic} =
      Forum.create_topic(author, general, %{"title" => "Chat", "body" => "Hi"})

    [opening] = Forum.list_messages(topic)
    {:ok, message} = Forum.post_message(author, topic, %{"body" => "Meet on Monday"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{author: author, topic: topic, opening: opening, message: message}
  end

  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  defp empty(lv, message) do
    lv |> element("#message-#{message.id} button", "Edit") |> render_click()
    lv |> form("#edit-message-#{message.id}", edit: %{body: ""}) |> render_submit()
  end

  @tag req: "GM-10"
  test "GM-10 the author deletes their own message: the topic counts it out, nothing logged",
       %{author: author, topic: topic, opening: opening, message: message} do
    count = Repo.reload!(topic).message_count

    assert Messages.delete_own(user_fixture(), message) == {:error, :forbidden}
    assert Messages.delete_own(author, opening) == {:error, :opening}

    {:ok, deleted} = Messages.delete_own(author, message)
    assert deleted.deleted_by_id == author.id
    assert Messages.deleted_by_author?(deleted)
    assert Repo.reload!(topic).message_count == count - 1
    assert Repo.aggregate(Action, :count) == 0

    assert Messages.delete_own(author, deleted) == {:error, :forbidden}
    assert Messages.edit(author, deleted, "Back") == {:error, :forbidden}
  end

  @tag req: "GM-10"
  test "GM-10 Yes deletes it: readers see Message deleted by user, moderators the text", %{
    author: author,
    topic: topic,
    message: message
  } do
    {:ok, lv, _html} = watch(log_in_user(build_conn(), author), topic)
    {:ok, reader, _html} = watch(build_conn(), topic)

    {:ok, moderator, _html} =
      watch(log_in_user(build_conn(), user_with_role_fixture(:moderator)), topic)

    empty(lv, message)
    assert has_element?(lv, "#delete-own-dialog button.btn-error", "Yes")
    lv |> element("#delete-own-dialog button", "Yes") |> render_click()

    refute has_element?(lv, "#delete-own-dialog")
    refute has_element?(lv, "#edit-message-#{message.id}")
    assert has_element?(lv, "#message-#{message.id}-deleted", "Message deleted by user")
    assert has_element?(reader, "#message-#{message.id}-deleted", "Message deleted by user")
    refute render(reader) =~ "Meet on Monday"

    assert has_element?(moderator, "#message-#{message.id}-deleted", "Deleted by user")
    assert has_element?(moderator, "#message-#{message.id}", "Meet on Monday")
  end

  @tag req: "GM-10"
  test "GM-10 runs of deletions read by kind; replies say who deleted the quoted message", %{
    author: author,
    topic: topic,
    message: message
  } do
    {:ok, other} = Forum.post_message(user_fixture(), topic, %{"body" => "Rude"})

    {:ok, reply} =
      Forum.post_message(user_fixture(), topic, %{"body" => "Sure", "reply_to_id" => message.id})

    {:ok, _} = Messages.delete_own(author, message)
    {:ok, _} = Messages.delete_as_moderator(user_with_role_fixture(:moderator), other)

    {:ok, reader, _html} = watch(build_conn(), topic)
    assert has_element?(reader, "#message-#{message.id}-deleted", "Message deleted by user")
    assert has_element?(reader, "#message-#{other.id}-deleted", "Message deleted by a moderator")
    assert has_element?(reader, "#message-#{reply.id}-reply-to", "Message deleted by user")
  end

  @tag req: "GM-10"
  test "GM-10 emptying the opening message is refused, with no question", %{
    author: author,
    topic: topic,
    opening: opening
  } do
    {:ok, lv, _html} = watch(log_in_user(build_conn(), author), topic)

    assert empty(lv, opening) =~ "can&#39;t be blank"
    refute has_element?(lv, "#delete-own-dialog")
  end
end

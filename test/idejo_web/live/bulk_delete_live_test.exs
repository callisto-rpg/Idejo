# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.BulkDeleteLiveTest do
  @moduledoc """
  "Select multiple messages for deletion" (MO-02; steward decision, 2026-10-23).
  """
  use IdejoWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Moderation.Action
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    moderator = user_with_role_fixture(:moderator)

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Picnic", "body" => "Saturday?"})

    [opening] = Forum.list_messages(topic)
    {:ok, a} = Forum.post_message(user_fixture(), topic, %{"body" => "Spam one"})
    {:ok, b} = Forum.post_message(user_fixture(), topic, %{"body" => "Spam two"})
    {:ok, mine} = Forum.post_message(moderator, topic, %{"body" => "Cleaning up"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{
      general: general,
      moderator: moderator,
      topic: topic,
      opening: opening,
      a: a,
      b: b,
      mine: mine
    }
  end

  defp open(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  @tag req: "MO-02"
  test "MO-02 deleting several messages at once: each logged, the topic counts them, own left",
       %{general: general, moderator: moderator, topic: topic, a: a, b: b, mine: mine} do
    count = Repo.reload!(topic).message_count

    {:ok, elsewhere} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Other", "body" => "Hi"})

    [far] = Forum.list_messages(elsewhere)

    assert {:ok, deleted} =
             Messages.delete_many_as_moderator(
               moderator,
               topic,
               [a.id, b.id, mine.id, far.id],
               "Spam"
             )

    assert Enum.map(deleted, & &1.id) |> Enum.sort() == Enum.sort([a.id, b.id])
    assert Enum.all?(deleted, &(&1.deleted_by_id == moderator.id))
    assert Repo.reload!(topic).message_count == count - 2
    assert is_nil(Repo.reload!(mine).deleted_at)
    assert is_nil(Repo.reload!(far).deleted_at)

    assert Repo.all(from x in Action, select: {x.action, x.reason}) ==
             [{"message.delete", "Spam"}, {"message.delete", "Spam"}]

    assert Messages.delete_many_as_moderator(moderator, topic, [mine.id]) == {:error, :none}

    assert Messages.delete_many_as_moderator(user_fixture(), topic, [a.id]) ==
             {:error, :forbidden}
  end

  @tag req: "MO-02"
  test "MO-02 Select multiple messages for deletion: choose, confirm, readers see one line", %{
    moderator: moderator,
    topic: topic,
    opening: opening,
    a: a,
    b: b,
    mine: mine
  } do
    {:ok, lv, _html} = open(log_in_user(build_conn(), moderator), topic)
    {:ok, reader, _html} = open(log_in_user(build_conn(), user_fixture()), topic)

    lv |> element("#message-#{a.id}-moderate") |> render_click()

    lv
    |> element("#moderate-card button", "Select multiple messages for deletion")
    |> render_click()

    refute has_element?(lv, "#moderate-card")
    refute has_element?(lv, "#move-banner")
    assert has_element?(lv, "#delete-banner", "Delete all selected messages")
    assert has_element?(lv, "#delete-banner", "1 message selected")
    assert has_element?(lv, "#select-#{a.id}[checked]")
    # The opening message may be deleted; the moderator's own messages are not offered.
    assert has_element?(lv, "#select-#{opening.id}")
    refute has_element?(lv, "#select-#{mine.id}")

    lv |> element("#select-#{b.id}") |> render_click()
    assert has_element?(lv, "#delete-banner", "2 messages selected")

    lv |> form("#delete-selected-form", %{reason: "Spam"}) |> render_submit()
    refute has_element?(lv, "#delete-banner")
    assert has_element?(lv, "#topic-info", "2 messages deleted.")

    assert has_element?(reader, "#message-#{a.id}-deleted", "2 messages deleted by a moderator")
    refute render(reader) =~ "Spam one"
  end

  @tag req: "MO-02"
  test "MO-02 cancelling the selection for deletion deletes nothing", %{
    moderator: moderator,
    topic: topic,
    a: a
  } do
    {:ok, lv, _html} = open(log_in_user(build_conn(), moderator), topic)
    lv |> element("#message-#{a.id}-moderate") |> render_click()

    lv
    |> element("#moderate-card button", "Select multiple messages for deletion")
    |> render_click()

    lv |> element("#delete-banner button", "Cancel") |> render_click()

    refute has_element?(lv, "#delete-banner")
    refute has_element?(lv, "#select-#{a.id}")
    assert is_nil(Repo.reload!(a).deleted_at)
  end
end

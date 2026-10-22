# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MoveMessagesLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff room"})

    for role <- [:guest, :member],
        do:
          {:ok, _} =
            Access.set_permission(admin, Access.built_in_role!(role), staff, :view, :deny)

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Picnic", "body" => "Saturday?"})

    [opening] = Forum.list_messages(topic)
    {:ok, a} = Forum.post_message(user_fixture(), topic, %{"body" => "Off topic one"})
    {:ok, b} = Forum.post_message(user_fixture(), topic, %{"body" => "Off topic two"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, staff: staff, topic: topic, opening: opening, a: a, b: b}
  end

  defp open(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  @tag req: "TP-15"
  test "TP-15 Moderate opens a card; Select to be moved shows checkboxes and the banner", %{
    topic: topic,
    opening: opening,
    a: a,
    b: b
  } do
    {:ok, lv, _html} = open(log_in_user(build_conn(), user_with_role_fixture(:moderator)), topic)
    {:ok, reader, _html} = open(log_in_user(build_conn(), user_fixture()), topic)
    refute has_element?(reader, "#message-#{a.id}-moderate")

    lv |> element("#message-#{a.id}-moderate") |> render_click()
    assert has_element?(lv, "dialog#moderate-card", "Moderate the message by")
    lv |> element("#moderate-card button", "Select to be moved") |> render_click()

    refute has_element?(lv, "#moderate-card")
    assert has_element?(lv, "#move-banner", "Move all selected messages to")
    assert has_element?(lv, "#move-banner", "1 message selected")
    assert has_element?(lv, "#select-#{a.id}[checked]")
    refute has_element?(lv, "#select-#{opening.id}")

    lv |> element("#select-#{b.id}") |> render_click()
    assert has_element?(lv, "#move-banner", "2 messages selected")

    # The opening message's card offers no moving.
    lv |> element("#message-#{opening.id}-moderate") |> render_click()
    refute has_element?(lv, "#moderate-card button", "Select to be moved")
    lv |> element("#moderate-card button", "Close") |> render_click()

    lv |> element("#move-banner button", "Cancel") |> render_click()
    refute has_element?(lv, "#move-banner")
    refute has_element?(lv, "#select-#{a.id}")
  end

  @tag req: "TP-15"
  test "TP-15 moving to a new thread, live for every viewer", %{
    general: general,
    topic: topic,
    a: a,
    b: b
  } do
    {:ok, lv, _html} = open(log_in_user(build_conn(), user_with_role_fixture(:moderator)), topic)
    {:ok, reader, _html} = open(build_conn(), topic)

    lv |> element("#message-#{a.id}-moderate") |> render_click()
    lv |> element("#moderate-card button", "Select to be moved") |> render_click()
    lv |> element("#select-#{b.id}") |> render_click()
    lv |> element("#move-banner button", "New thread") |> render_click()

    assert has_element?(lv, "dialog#move-dialog", "Move 2 messages to a new thread")

    html =
      lv
      |> form("#move-new-form", %{title: "Off topic", category_id: general.id, reason: "Split"})
      |> render_submit()

    assert html =~ "2 messages moved to “Off topic”."
    refute has_element?(lv, "#move-banner")
    refute has_element?(lv, "#message-#{a.id}")
    refute has_element?(reader, "#message-#{b.id}")
    assert Forum.get_viewable_message(nil, a.id).topic.title == "Off topic"
  end

  @tag req: "TP-15"
  test "TP-15 moving to an existing thread found by its title", %{
    general: general,
    topic: topic,
    a: a
  } do
    {:ok, other} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Weather talk", "body" => "Rain?"})

    {:ok, lv, _html} = open(log_in_user(build_conn(), user_with_role_fixture(:moderator)), topic)

    lv |> element("#message-#{a.id}-moderate") |> render_click()
    lv |> element("#moderate-card button", "Select to be moved") |> render_click()
    lv |> element("#move-banner button", "Existing thread") |> render_click()

    lv |> form("#move-existing-form", %{q: "weath"}) |> render_change()
    assert has_element?(lv, "#move-existing-form label", "Weather talk")

    lv |> form("#move-existing-form", %{topic_id: other.id}) |> render_submit()
    assert Idejo.Repo.reload!(a).topic_id == other.id
  end

  @tag req: "TP-15"
  test "TP-15 a reply moved away from a reader keeps its quote only for those who may see it", %{
    admin: admin,
    staff: staff,
    topic: topic,
    a: a
  } do
    {:ok, reply} =
      Forum.post_message(user_fixture(), topic, %{"body" => "Agreed", "reply_to_id" => a.id})

    {:ok, _} =
      Forum.move_messages(
        admin,
        topic,
        [a.id],
        {:new, %{"title" => "Staff only", "category_id" => staff.id}}
      )

    {:ok, reader, _html} = open(build_conn(), topic)

    assert has_element?(
             reader,
             "#message-#{reply.id}-reply-to",
             "In reply to a message in another thread"
           )

    refute has_element?(reader, "#message-#{reply.id}-reply-to", "Off topic one")

    {:ok, staff_view, _html} = open(log_in_user(build_conn(), admin), topic)
    assert has_element?(staff_view, "#message-#{reply.id}-reply-to", "Off topic one")
  end
end

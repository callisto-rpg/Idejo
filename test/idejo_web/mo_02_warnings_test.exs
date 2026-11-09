# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MO02WarningsTest do
  @moduledoc """
  MO-02 "warn" (steward request, 2026-11-09): a moderator warns a message's author with a
  reason; the author gets a bubble and a card, at once or on their next page.
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Forum
  alias Idejo.Moderation
  alias Idejo.Moderation.{Warning, Warnings}
  alias Idejo.Notifications
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, other} = Forum.create_category(admin, %{"name" => "Other"})
    member = user_fixture(%{display_name: "Bo"})
    {:ok, topic} = Forum.create_topic(member, general, %{"title" => "Plans", "body" => "Hi"})
    {:ok, message} = Forum.post_message(member, topic, %{"body" => "Rude words"})
    {:ok, elsewhere} = Forum.create_topic(member, other, %{"title" => "Else", "body" => "Hey"})
    [opening] = Forum.list_messages(elsewhere)

    %{
      admin: admin,
      general: general,
      member: member,
      topic: topic,
      message: message,
      elsewhere: opening
    }
  end

  defp category_moderator(admin, category) do
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Mods")})
    {:ok, _} = Access.set_permission(admin, role, category, :moderate, :allow)
    user = user_fixture(%{display_name: "Mod"})
    {:ok, _} = Access.assign_role(admin, user, role)
    user
  end

  @tag req: "MO-02"
  test "MO-02 a moderator of the category warns a message's author, logged, told at once", %{
    admin: admin,
    general: general,
    member: member,
    message: message,
    elsewhere: elsewhere
  } do
    mod = category_moderator(admin, general)
    Notifications.subscribe(member)

    assert {:error, :forbidden} = Warnings.warn(user_fixture(), message, "No")
    assert {:error, :forbidden} = Warnings.warn(mod, elsewhere, "Not my category")
    assert {:error, :reason} = Warnings.warn(mod, message, "  ")
    assert {:error, :reason} = Warnings.warn(mod, message, String.duplicate("a", 1001))

    assert {:ok, %Warning{} = warning} = Warnings.warn(mod, message, "Be civil, please.")
    assert warning.user_id == member.id
    assert warning.category_id == general.id
    assert_receive {:warning, %Warning{reason: "Be civil, please."}}

    assert Repo.get!(User, member.id).warning_pending

    {[entry], _more?} = Moderation.list(mod)
    assert entry.action == "user.warn"
    assert entry.target_id == member.id
    assert entry.category_id == general.id
    assert entry.reason == "Be civil, please."
  end

  @tag req: "MO-02"
  test "MO-02 owners, administrators, oneself and deleted messages are not warned", %{
    admin: admin,
    general: general,
    topic: topic,
    message: message
  } do
    mod = category_moderator(admin, general)
    {:ok, own} = Forum.post_message(mod, topic, %{"body" => "Mine"})
    {:ok, by_admin} = Forum.post_message(admin, topic, %{"body" => "Admin here"})

    assert {:error, :not_warnable} = Warnings.warn(mod, own, "Me")
    assert {:error, :not_warnable} = Warnings.warn(mod, by_admin, "Boss")

    {:ok, deleted} = Idejo.Messages.delete_as_moderator(mod, message, "spam")
    assert {:error, :forbidden} = Warnings.warn(mod, deleted, "Gone")
  end

  @tag req: "MO-02"
  test "MO-02 moderators see the warnings of the categories they moderate; administrators all",
       %{admin: admin, general: general, member: member, message: message, elsewhere: elsewhere} do
    mod = category_moderator(admin, general)
    {:ok, _} = Warnings.warn(mod, message, "First")
    {:ok, _} = Warnings.warn(admin, elsewhere, "Second, elsewhere")

    assert Warnings.count_visible(mod, member) == 1
    assert [%{reason: "First", moderator: %{display_name: "Mod"}}] = Warnings.visible(mod, member)
    assert Warnings.count_visible(admin, member) == 2

    assert Enum.map(Warnings.visible(admin, member), & &1.reason) == [
             "Second, elsewhere",
             "First"
           ]
  end

  @tag req: "MO-02"
  test "MO-02 \"Warn user\" opens the card, with the earlier warnings, and warns", %{
    conn: conn,
    admin: admin,
    general: general,
    member: member,
    topic: topic,
    message: message
  } do
    mod = category_moderator(admin, general)
    {:ok, _} = Warnings.warn(mod, message, "Earlier warning")

    {:ok, view, _html} =
      live_isolated(log_in_user(conn, mod), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    # Not on one's own messages; on the member's.
    {:ok, own} = Forum.post_message(mod, topic, %{"body" => "Mine"})
    send(view.pid, {:message, Idejo.Repo.preload(own, Idejo.Messages.shown())})
    refute has_element?(view, "#message-#{own.id}-warn")

    view |> element("#message-#{message.id}-warn") |> render_click()
    assert has_element?(view, "#warn-dialog-title", "Warn Bo")
    assert has_element?(view, "#warn-history", "View 1 previous warning")

    view |> form("#warn-form", warning: %{reason: "Kept while looking"}) |> render_change()
    view |> element("#warn-history") |> render_click()
    assert has_element?(view, "#warn-previous li", "Earlier warning")
    assert has_element?(view, "#warn-reason", "Kept while looking")

    assert view |> form("#warn-form", warning: %{reason: " "}) |> render_submit() =~
             "Write the reason"

    html = view |> form("#warn-form", warning: %{reason: "Last warning."}) |> render_submit()
    assert html =~ "Bo is warned."
    refute has_element?(view, "#warn-dialog")
    assert Warnings.count_visible(mod, member) == 2
  end

  @tag req: "MO-02"
  test "MO-02 the warned member gets a bubble and the card at once, or on their next page", %{
    conn: conn,
    admin: admin,
    member: member,
    message: message
  } do
    conn = log_in_user(conn, member)
    {:ok, lv, html} = live_isolated(conn, IdejoWeb.NotifierLive)
    refute html =~ "warning-card"

    {:ok, _} = Warnings.warn(admin, message, "Keep it friendly.")
    assert_push_event(lv, "notification", %{kind: "warning", text: "A moderator warned you"})
    assert has_element?(lv, "#warning-card", "Keep it friendly.")

    # Not acknowledged: every page shows it again; without JavaScript, open, with a form.
    page = build_conn() |> log_in_user(member) |> get(~p"/") |> html_response(200)
    assert page =~ ~s(id="warning-card")
    assert page =~ ~s(action="/warnings/seen")
    assert page =~ "Keep it friendly."

    lv |> element("#warning-card form") |> render_submit()
    refute has_element?(lv, "#warning-card")
    refute Repo.get!(User, member.id).warning_pending
    assert Warnings.pending(Repo.get!(User, member.id)) == []

    page = build_conn() |> log_in_user(member) |> get(~p"/") |> html_response(200)
    refute page =~ ~s(id="warning-card")
  end

  @tag req: "MO-02"
  test "MO-02 \"I understand\" works without JavaScript", %{
    conn: conn,
    admin: admin,
    member: member,
    message: message
  } do
    {:ok, _} = Warnings.warn(admin, message, "Read the rules.")

    conn =
      conn
      |> log_in_user(member)
      |> put_req_header("referer", "http://www.example.com/rules")
      |> post(~p"/warnings/seen")

    assert redirected_to(conn) == "/rules"
    refute Repo.get!(User, member.id).warning_pending
  end
end

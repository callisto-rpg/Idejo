# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Email notifications in the profile, and the unsubscribe link (steward decision, 2026-10-23,
# with NO-04).
defmodule IdejoWeb.EmailNotificationsTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts.User
  alias Idejo.Notifications.{Digest, EmailPreference}
  alias Idejo.Repo

  test "the profile's Email notifications: the options, two of them on, and once a week" do
    user = user_fixture()
    {:ok, lv, html} = live(log_in_user(build_conn(), user), ~p"/users/settings")

    assert html =~ "Email notifications"

    assert html =~
             "If I haven&#39;t logged in for 24 hours, send me a summary of activity if there are:"

    assert html =~ "@#{user.username} mentions and replies to my posts"

    checked = fn name ->
      has_element?(
        lv,
        ~s(#email-notifications-form input[type=checkbox][name="email[#{name}]"][checked])
      )
    end

    assert checked.("mentions") and checked.("own_topics") and checked.("once_a_week")
    refute checked.("role_mentions") or checked.("followed_topics")
    refute checked.("new_topics") or checked.("all_activity")

    assert lv
           |> form("#email-notifications-form",
             email: %{followed_topics: "true", own_topics: "false", once_a_week: "false"}
           )
           |> render_submit() =~ "Email notifications saved."

    preference = Digest.preferences(user)
    assert preference.followed_topics and preference.mentions
    refute preference.own_topics or preference.once_a_week
  end

  test "the unsubscribe link: a page with one button, and mail programs' one-click post" do
    user = user_fixture()
    {:ok, _} = Digest.update_preferences(user, %{})
    Repo.update_all(EmailPreference, set: [unsubscribe_token: "tok-#{user.id}"])
    token = "tok-#{user.id}"

    html = build_conn() |> get(~p"/email/unsubscribe/#{token}") |> html_response(200)
    assert html =~ "Stop these emails"

    # The page's form, without any session.
    conn = post(build_conn(), ~p"/email/unsubscribe/#{token}")
    assert redirected_to(conn) == "/email/unsubscribe/#{token}?done=1"
    refute Digest.preferences(user).mentions

    assert build_conn() |> get(~p"/email/unsubscribe/#{token}?done=1") |> html_response(200) =~
             "you will get no more summaries"

    # RFC 8058.
    {:ok, _} = Digest.update_preferences(user, %{"mentions" => "true"})

    conn =
      post(build_conn(), ~p"/email/unsubscribe/#{token}", %{"List-Unsubscribe" => "One-Click"})

    assert response(conn, 200) == "Unsubscribed"
    refute Digest.preferences(user).mentions

    assert build_conn() |> post(~p"/email/unsubscribe/unknown") |> response(404)
  end

  test "a page load marks the user seen" do
    user = user_fixture()
    Repo.update_all(User, set: [last_seen_at: ~U[2026-01-01 00:00:00Z]])
    build_conn() |> log_in_user(user) |> get(~p"/")
    seen = Repo.get!(User, user.id).last_seen_at
    assert DateTime.diff(DateTime.utc_now(), seen) < 5
  end
end

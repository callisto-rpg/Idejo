# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserTagTest do
  # The user tag (steward decision, 2026-10-27), part of the profile (AC-04).
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Forum

  setup %{conn: conn} do
    user = user_fixture(%{display_name: "Ada", password: "a long enough password"})
    %{conn: log_in_user(conn, user), user: user}
  end

  @tag req: "AC-04"
  test "AC-04 a user sets and clears their user tag from the profile", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert {:error, {:redirect, %{to: "/users/settings"}}} =
             lv
             |> form("#profile-form",
               profile: %{display_name: "Ada", user_tag: "  the Countess "}
             )
             |> render_submit()

    assert Accounts.get_user(user.id).user_tag == "the Countess"

    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert {:error, {:redirect, _}} =
             lv
             |> form("#profile-form", profile: %{display_name: "Ada", user_tag: "   "})
             |> render_submit()

    assert Accounts.get_user(user.id).user_tag == nil
  end

  @tag req: "AC-04"
  test "AC-04 the user tag is at most 32 characters", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert lv
           |> form("#profile-form",
             profile: %{display_name: "Ada", user_tag: String.duplicate("a", 33)}
           )
           |> render_submit() =~ "should be at most 32 character(s)"

    assert Accounts.get_user(user.id).user_tag == nil
  end

  @tag req: "AC-04"
  test "AC-04 the user tag shows after the name, inside the link to the card", %{user: user} do
    {:ok, user} = Accounts.update_user_profile(user, %{"user_tag" => "the Countess"})
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Forum.create_topic(user, general, %{"title" => "Hello", "body" => "Hi"})
    [message] = Forum.list_messages(topic)

    doc =
      build_conn()
      |> get(~p"/t/#{topic.id}/#{topic.slug}")
      |> html_response(200)
      |> LazyHTML.from_document()

    link =
      LazyHTML.query(doc, ~s(#message-#{message.id}-author a.author-name[href="/u/#{user.id}"]))

    assert link |> LazyHTML.query(".user-tag") |> LazyHTML.text() == "the Countess"
    assert LazyHTML.text(link) =~ "Ada"

    card =
      build_conn() |> get(~p"/u/#{user.id}") |> html_response(200) |> LazyHTML.from_document()

    assert card |> LazyHTML.query("#user-card-name .user-tag") |> LazyHTML.text() ==
             "the Countess"

    # Without one, nothing.
    other = user_fixture()
    card = build_conn() |> get(~p"/u/#{other.id}") |> html_response(200)
    refute card =~ "user-tag"
  end

  @tag req: "AC-07"
  test "AC-07 deleting the account removes the user tag", %{user: user} do
    {:ok, user} = Accounts.update_user_profile(user, %{"user_tag" => "the Countess"})
    {:ok, _} = Accounts.delete_user(user, "a long enough password")
    assert Accounts.get_user(user.id).user_tag == nil
  end
end

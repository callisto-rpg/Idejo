# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserBioTest do
  use IdejoWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Federation.Activity
  alias Idejo.Repo

  setup %{conn: conn} do
    user = user_fixture(%{display_name: "Ada"})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp card(user) do
    build_conn() |> get(~p"/u/#{user.id}") |> html_response(200) |> LazyHTML.from_document()
  end

  @tag req: "AC-04"
  test "AC-04 a user writes a Markdown bio, shown on their page under their roles", %{
    conn: conn,
    user: user
  } do
    friend = user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    bio = "Loves **beans**.\n\nAsk @#{friend.username}.\n\n<script>alert(1)</script>"

    lv |> form("#bio-form", bio: %{bio_md: bio}) |> render_change()
    lv |> element("#bio_bio_md-preview-tab") |> render_click()
    assert has_element?(lv, "#bio_bio_md-preview strong", "beans")

    lv |> form("#bio-form", bio: %{bio_md: bio}) |> render_submit()
    user = Accounts.get_user(user.id)
    assert user.bio_md == bio
    refute user.bio_html =~ "<script"

    doc = card(user)
    bio_el = LazyHTML.query(doc, "#user-card-bio")
    assert bio_el |> LazyHTML.query("strong") |> LazyHTML.text() == "beans"
    assert bio_el |> LazyHTML.query(~s(a[href="/u/#{friend.id}"])) |> Enum.count() == 1
    # Under the roles.
    assert LazyHTML.to_html(doc) =~ ~r/aria-label="Roles".*id="user-card-bio"/s

    assert [%{payload: %{"summary" => summary}}] =
             Repo.all(
               from a in Activity,
                 where: a.object_uri == ^user.uri and a.verb == "update"
             )

    assert summary == user.bio_html

    # Emptied: none.
    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    lv |> form("#bio-form", bio: %{bio_md: "  "}) |> render_submit()
    assert Accounts.get_user(user.id).bio_html == nil
    assert card(user) |> LazyHTML.query("#user-card-bio") |> Enum.count() == 0
  end

  @tag req: "AC-04"
  test "AC-04 the bio is at most 5000 characters", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert lv
           |> form("#bio-form", bio: %{bio_md: String.duplicate("a", 5001)})
           |> render_submit() =~ "should be at most 5000 character(s)"

    assert Accounts.get_user(user.id).bio_md == nil
  end

  @tag req: "AC-07"
  test "AC-07 deleting the account removes the bio", %{user: user} do
    {:ok, user} = Accounts.update_user_bio(user, %{"bio_md" => "Hello"})
    {:ok, _} = Accounts.delete_user(user, valid_user_password())
    deleted = Accounts.get_user(user.id)
    assert deleted.bio_md == nil and deleted.bio_html == nil
  end
end

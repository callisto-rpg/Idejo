# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSettingsLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Federation.Activity
  alias Idejo.Repo

  setup %{conn: conn} do
    user = user_fixture(%{display_name: "Ada Lovelace"})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp updates(user) do
    Repo.all(from a in Activity, where: a.object_uri == ^user.uri and a.verb == "update")
  end

  @tag req: "AC-04"
  test "AC-04 visitors are sent to sign in" do
    assert {:error, {:redirect, %{to: "/users/sign-in"}}} =
             live(build_conn(), ~p"/users/settings")
  end

  @tag req: "AC-04"
  test "AC-04 a user changes their display name", %{conn: conn, user: user} do
    {:ok, lv, html} = live(conn, ~p"/users/settings")
    assert html =~ "@#{user.username}"

    assert {:error, {:redirect, %{to: "/users/settings"}}} =
             lv
             |> form("#profile-form", profile: %{display_name: "  Ada King  "})
             |> render_submit()

    user = Accounts.get_user(user.id)
    assert user.display_name == "Ada King"

    assert [%{payload: %{"type" => "Person", "name" => "Ada King"}, actor_uri: actor}] =
             updates(user)

    assert actor == user.uri

    # The header shows the new name after the page reloads.
    html = conn |> get(~p"/users/settings") |> html_response(200)
    assert html =~ ~s(href="/users/settings">Ada King)
  end

  @tag req: "AC-04"
  test "AC-04 the display name is required and at most 60 characters", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert lv |> form("#profile-form", profile: %{display_name: "   "}) |> render_submit() =~
             "can&#39;t be blank"

    assert lv
           |> form("#profile-form", profile: %{display_name: String.duplicate("a", 61)})
           |> render_change() =~ "should be at most 60 character"

    assert Accounts.get_user(user.id).display_name == "Ada Lovelace"
    assert updates(user) == []
  end

  @tag req: "AC-04"
  test "AC-04 saving an unchanged name records nothing", %{user: user} do
    assert {:ok, _} = Accounts.update_user_profile(user, %{"display_name" => "Ada Lovelace"})
    assert updates(user) == []
  end

  @tag req: "AC-04"
  test "AC-04 the username cannot be changed from the profile", %{user: user} do
    {:ok, updated} = Accounts.update_user_profile(user, %{"username" => "someone_else"})
    assert updated.username == user.username
  end
end

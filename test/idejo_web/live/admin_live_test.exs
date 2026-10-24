# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AdminLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Audit
  alias Idejo.Settings

  describe "access" do
    @tag req: "AD-02"
    test "AD-02 visitors are sent to sign in", %{conn: conn} do
      for path <- [~p"/admin", ~p"/admin/users"] do
        assert redirected_to(get(conn, path)) == ~p"/users/sign-in"
      end
    end

    @tag req: "AD-02"
    test "AD-02 members and moderators are refused", %{conn: conn} do
      for user <- [user_fixture(), user_with_role_fixture(:moderator)] do
        conn = conn |> log_in_user(user) |> get(~p"/admin")
        assert redirected_to(conn) == ~p"/"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Only administrators"
      end
    end

    @tag req: "AD-02"
    test "AD-02 owners and administrators get in even before verifying their email", %{
      conn: conn
    } do
      for role <- [:owner, :administrator] do
        user = unconfirmed_user_fixture()
        :ok = Access.grant_role(user, Access.built_in_role!(role))

        conn = conn |> log_in_user(user) |> get(~p"/admin")
        assert html_response(conn, 200) =~ "Server name"
      end
    end

    @tag req: "AD-02"
    test "AD-02 owners and administrators get in", %{conn: conn} do
      for role <- [:owner, :administrator] do
        conn = conn |> log_in_user(user_with_role_fixture(role)) |> get(~p"/admin")
        assert html_response(conn, 200) =~ "Server name"
      end
    end

    @tag req: "AD-02"
    test "AD-02 the live socket checks again when it connects", %{conn: conn} do
      admin = user_with_role_fixture(:administrator)
      conn = log_in_user(conn, admin)
      {:ok, _lv, _html} = live(conn, ~p"/admin")

      # Losing the role between page load and socket connect closes the door.
      Idejo.Repo.delete_all(Access.UserRole)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
    end

    @tag req: "AD-02"
    test "AD-02 the Admin link shows only to administrators", %{conn: conn} do
      refute conn |> log_in_user(user_fixture()) |> get(~p"/") |> html_response(200) =~
               ~s(href="/admin")

      assert conn
             |> log_in_user(user_with_role_fixture(:administrator))
             |> get(~p"/")
             |> html_response(200) =~ ~s(href="/admin")
    end
  end

  describe "settings" do
    setup %{conn: conn} do
      admin = user_with_role_fixture(:administrator)
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    @tag req: "AD-02"
    test "AD-02 an administrator changes the server name", %{conn: conn, admin: admin} do
      {:ok, lv, html} = live(conn, ~p"/admin")
      assert html =~ ~s(value="Idejo")

      html =
        lv
        |> form("#settings-form", settings: %{server_name: "Lumière"})
        |> render_submit()

      assert html =~ "Settings saved."
      assert Settings.get(:server_name) == "Lumière"
      assert [%{admin_id: admin_id, change: "settings.update"}] = Audit.list_entries()
      assert admin_id == admin.id
    end

    @tag req: "AD-02"
    test "AD-02 an administrator sets the website theme", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/admin")
      assert html =~ ~s(value="#daa304ff")
      assert html =~ ~s(value="#daa304")

      # The colour picker fills in the hex field.
      html =
        lv
        |> form("#settings-form")
        |> render_change(%{
          "_target" => ["settings", "theme_secondary_picker"],
          "settings" => %{"theme_secondary_picker" => "#112233"}
        })

      assert html =~ ~s(value="#112233")

      # A theme change loads the page again, so the panel shows it.
      assert {:error, {:redirect, %{to: "/admin"}}} =
               lv
               |> form("#settings-form", settings: %{theme_primary: "#3366ff"})
               |> render_submit()

      assert Settings.theme().primary == "#3366ff"
      assert conn |> get(~p"/") |> html_response(200) =~ "--color-primary:#3366ff;"
    end

    @tag req: "AD-02"
    test "AD-02 invalid settings show errors and save nothing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin")

      assert lv |> form("#settings-form", settings: %{server_name: ""}) |> render_change() =~
               "can&#39;t be blank"

      assert lv |> form("#settings-form", settings: %{server_name: ""}) |> render_submit() =~
               "can&#39;t be blank"

      assert Settings.get(:server_name) == "Idejo"
    end
  end

  describe "users" do
    setup %{conn: conn} do
      admin = user_with_role_fixture(:administrator, %{display_name: "Grace Admin"})
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    @tag req: "AD-02"
    test "AD-02 lists users with their roles and verification", %{conn: conn} do
      unverified = unconfirmed_user_fixture(%{display_name: "Nina New"})
      moderator = user_with_role_fixture(:moderator, %{display_name: "Max Mod"})

      {:ok, lv, _html} = live(conn, ~p"/admin/users")

      assert lv |> element("#user-#{unverified.id}") |> render() =~ "unverified"
      assert lv |> element("#user-#{unverified.id}") |> render() =~ "Guest"
      assert lv |> element("#user-#{moderator.id}") |> render() =~ "Moderator, Member"
      assert lv |> element("tbody") |> render() =~ "Administrator, Member"
    end

    @tag req: "AD-02"
    test "AD-02 an unverified administrator is listed with the administrator role", %{
      conn: conn
    } do
      user = unconfirmed_user_fixture()
      :ok = Access.grant_role(user, Access.built_in_role!(:administrator))
      :ok = Access.grant_role(user, Access.built_in_role!(:moderator))

      {:ok, lv, _html} = live(conn, ~p"/admin/users")
      assert lv |> element("#user-#{user.id}") |> render() =~ "Administrator, Guest"
    end

    @tag req: "AD-02"
    test "AD-02 users are listed in pages", %{conn: conn} do
      for _ <- 1..50, do: unconfirmed_user_fixture()

      {:ok, lv, html} = live(conn, ~p"/admin/users")
      assert html =~ "Next page"
      refute lv |> element("tbody") |> render() =~ "Grace Admin"

      html = lv |> element("a", "Next page") |> render_click()
      assert lv |> element("tbody") |> render() =~ "Grace Admin"
      assert html =~ "Previous page"
      refute html =~ "Next page"
    end

    @tag req: "AD-02"
    test "AD-02 shows one user's details", %{conn: conn} do
      user = user_fixture(%{display_name: "Ada Lovelace"})
      {:ok, _lv, html} = live(conn, ~p"/admin/users/#{user.id}")

      assert html =~ "Ada Lovelace"
      assert html =~ user.email
      assert html =~ user.uri
      assert html =~ "Member"
    end

    @tag req: "AD-02"
    test "AD-02 an unknown user is not found", %{conn: conn} do
      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert_error_sent 404, fn -> get(conn, ~p"/admin/users/#{id}") end
      end
    end
  end
end

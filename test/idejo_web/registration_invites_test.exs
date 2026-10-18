# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.RegistrationInvitesTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Accounts.Invite
  alias Idejo.Settings

  import Ecto.Query, only: [from: 2]

  describe "sign-up page" do
    @tag req: "AC-02"
    test "AC-02 while open, there is no invite field", %{conn: conn} do
      html = conn |> get(~p"/users/sign-up") |> html_response(200)
      refute html =~ ~s(name="user[invite_code]")
    end

    @tag req: "AC-02"
    test "AC-02 while invite-only, the form asks for the invite and fills it from the link", %{
      conn: conn
    } do
      invite_only!()
      html = conn |> get(~p"/users/sign-up?invite=abc123") |> html_response(200)

      assert html =~ "Joining is by invitation"
      assert html =~ ~s(name="user[invite_code]")
      assert html =~ ~s(value="abc123")
    end

    @tag req: "AC-02"
    test "AC-02 signing up with an invite link works once", %{conn: conn} do
      invite = invite_only!() |> invite_fixture()
      attrs = valid_user_attributes(invite_code: invite.code)

      conn = post(conn, ~p"/users/sign-up", %{"user" => attrs})
      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)

      html =
        build_conn()
        |> post(~p"/users/sign-up", %{"user" => valid_user_attributes(invite_code: invite.code)})
        |> html_response(200)

      assert html =~ "is not valid, used or expired"
    end

    @tag req: "AC-02"
    test "AC-02 without an invite the sign-up is refused", %{conn: conn} do
      invite_only!()
      # The form always sends the field, empty when no code is given.
      conn = post(conn, ~p"/users/sign-up", %{"user" => valid_user_attributes(invite_code: "")})

      assert html_response(conn, 200) =~ "is not valid, used or expired"
      refute get_session(conn, :user_token)
    end
  end

  describe "admin" do
    setup %{conn: conn} do
      admin = user_with_role_fixture(:administrator)
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    @tag req: "AC-02"
    test "AC-02 an administrator switches registration to invite-only", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin")

      lv
      |> form("#settings-form", settings: %{registration_mode: "invite_only"})
      |> render_submit()

      assert Settings.get(:registration_mode) == "invite_only"
    end

    @tag req: "AC-02"
    test "AC-02 an administrator creates an invite link to copy", %{conn: conn, admin: admin} do
      invite_only!(admin)
      {:ok, lv, html} = live(conn, ~p"/admin/invites")
      refute html =~ "invites are not needed"

      html = lv |> element("#create-invite") |> render_click()

      assert [%Invite{code: code}] = Accounts.list_invites()
      assert html =~ "copy it and send it to one person"
      assert lv |> element("#new-invite-url") |> render() =~ "/users/sign-up?invite=#{code}"
      assert lv |> element("#invite-#{code}") |> render() =~ "Unused"
    end

    @tag req: "AC-02"
    test "AC-02 the list shows used and expired invites", %{conn: conn, admin: admin} do
      invite_only!(admin)
      used = invite_fixture(admin)
      expired = invite_fixture(admin)

      {:ok, _} =
        Accounts.register_user(valid_user_attributes(display_name: "Nia", invite_code: used.code))

      Idejo.Repo.update_all(
        from(i in Invite, where: i.code == ^expired.code),
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -60)]
      )

      {:ok, lv, _html} = live(conn, ~p"/admin/invites")
      assert lv |> element("#invite-#{used.code}") |> render() =~ "Used by Nia"
      assert lv |> element("#invite-#{expired.code}") |> render() =~ "Expired"
      refute lv |> element("#invite-#{used.code}") |> render() =~ "invite=#{used.code}"
    end

    @tag req: "AC-02"
    test "AC-02 while open, the invites page says invites are not needed", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/invites")
      assert html =~ "invites are not needed"
    end

    @tag req: "AC-02"
    test "AC-02 only administrators can create invites" do
      conn = build_conn() |> log_in_user(user_fixture()) |> get(~p"/admin/invites")
      assert redirected_to(conn) == ~p"/"
    end
  end
end

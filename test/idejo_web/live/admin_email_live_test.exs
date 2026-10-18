# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AdminEmailLiveTest do
  # One test switches the mailer adapter, so not async.
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Idejo.AccountsFixtures

  alias Idejo.Audit
  alias Idejo.Settings

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  @tag req: "AD-08"
  test "AD-08 only administrators can open the email settings" do
    conn = build_conn() |> log_in_user(user_fixture()) |> get(~p"/admin/email")
    assert redirected_to(conn) == ~p"/"
  end

  @tag req: "AD-08"
  test "AD-08 an administrator saves the SMTP settings", %{conn: conn, admin: admin} do
    {:ok, lv, html} = live(conn, ~p"/admin/email")
    assert html =~ "SMTP host"

    html =
      lv
      |> form("#email-form",
        settings: %{
          mail_from: "forum@example.org",
          smtp_host: "smtp.example.org",
          smtp_port: "587",
          smtp_security: "starttls",
          smtp_username: "forum",
          smtp_password: "s3cret-pass"
        }
      )
      |> render_submit()

    assert html =~ "Email settings saved."
    assert html =~ "saved; leave empty to keep it"
    refute html =~ "s3cret-pass"
    assert Settings.get(:smtp_host) == "smtp.example.org"
    assert [%{admin_id: admin_id}] = Audit.list_entries()
    assert admin_id == admin.id
  end

  @tag req: "AD-08"
  test "AD-08 the saved password is never sent to the browser", %{conn: conn, admin: admin} do
    {:ok, _} =
      Settings.update_settings(admin, %{
        "smtp_host" => "smtp.example.org",
        "smtp_password" => "s3cret-pass"
      })

    {:ok, lv, html} = live(conn, ~p"/admin/email")
    refute html =~ "s3cret-pass"
    refute render(lv) =~ "s3cret-pass"
  end

  @tag req: "AD-08"
  test "AD-08 invalid values show errors", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/email")

    html = lv |> form("#email-form", settings: %{smtp_port: "0"}) |> render_submit()
    assert html =~ "must be greater than or equal to 1"
    assert Settings.get(:smtp_port) == 587
  end

  @tag req: "AD-08"
  test "AD-08 the test button sends an email to the administrator", %{conn: conn, admin: admin} do
    # The fixture's verification email comes first.
    assert_email_sent(subject: "Verify your email address")
    {:ok, lv, _html} = live(conn, ~p"/admin/email")

    lv |> element("#send-test-email") |> render_click()
    assert render_async(lv) =~ "Test email sent to #{admin.email}."
    assert_email_sent(to: admin.email, subject: "Test email from Idejo")
  end

  @tag req: "AD-08"
  test "AD-08 the test button explains why sending failed", %{conn: conn} do
    previous = Application.get_env(:idejo, Idejo.Mailer)
    Application.put_env(:idejo, Idejo.Mailer, adapter: Swoosh.Adapters.SMTP)
    on_exit(fn -> Application.put_env(:idejo, Idejo.Mailer, previous) end)

    {:ok, lv, _html} = live(conn, ~p"/admin/email")

    lv |> element("#send-test-email") |> render_click()
    assert render_async(lv) =~ "Set an SMTP host and save before sending a test email."
  end
end

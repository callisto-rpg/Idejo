# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.EmailSettingsTest do
  # Switches the mailer adapter in some tests, so not async.
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Accounts.UserNotifier
  alias Idejo.Audit
  alias Idejo.Mailer
  alias Idejo.Settings
  alias Idejo.Settings.{Secret, Setting}

  @smtp %{
    "mail_from" => "forum@example.org",
    "smtp_host" => "smtp.example.org",
    "smtp_port" => "465",
    "smtp_security" => "tls",
    "smtp_username" => "forum",
    "smtp_password" => "s3cret-pass"
  }

  setup do
    %{admin: user_with_role_fixture(:administrator)}
  end

  describe "email settings" do
    @tag req: "AD-08"
    test "AD-08 defaults: email off, STARTTLS on 587, sender noreply@<host>" do
      assert %{
               smtp_host: "",
               smtp_port: 587,
               smtp_security: "starttls",
               smtp_username: "",
               smtp_password: "",
               mail_from: "noreply@localhost"
             } = Settings.all()

      assert {:error, :smtp_not_configured} = Mailer.smtp_config(Settings.all())
    end

    @tag req: "AD-08"
    test "AD-08 saving SMTP settings stores them and audits every change", %{admin: admin} do
      assert {:ok, _} = Settings.update_settings(admin, @smtp)

      assert %{
               smtp_host: "smtp.example.org",
               smtp_port: 465,
               smtp_security: "tls",
               smtp_username: "forum",
               smtp_password: "s3cret-pass",
               mail_from: "forum@example.org"
             } = Settings.all()

      assert [%{change: "settings.update", before: before, after: after_}] = Audit.list_entries()
      assert after_["smtp_host"] == "smtp.example.org"
      assert after_["smtp_port"] == 465
      assert before["smtp_port"] == 587
    end

    @tag req: "AD-08"
    test "AD-08 the SMTP password is encrypted at rest and never audited", %{admin: admin} do
      {:ok, _} = Settings.update_settings(admin, @smtp)

      stored = Repo.get!(Setting, "smtp_password").value
      refute stored =~ "s3cret-pass"
      assert Secret.decrypt(stored) == "s3cret-pass"

      [entry] = Audit.list_entries()
      assert entry.before["smtp_password"] == "[hidden]"
      assert entry.after["smtp_password"] == "[changed]"
      refute inspect(Repo.all(Idejo.Audit.Entry)) =~ "s3cret-pass"
    end

    @tag req: "AD-08"
    test "AD-08 a blank password keeps the saved one", %{admin: admin} do
      {:ok, _} = Settings.update_settings(admin, @smtp)

      assert {:ok, _} =
               Settings.update_settings(admin, %{
                 @smtp
                 | "smtp_password" => "",
                   "smtp_port" => "587"
               })

      assert Settings.get(:smtp_password) == "s3cret-pass"
      assert Settings.secret_set?(:smtp_password)
      # Only the port changed the second time.
      assert [%{after: after_} | _] = Audit.list_entries()
      assert Map.keys(after_) == ["smtp_port"]
    end

    @tag req: "AD-08"
    test "AD-08 a password that cannot be decrypted reads as not set", %{admin: admin} do
      {:ok, _} = Settings.update_settings(admin, @smtp)

      Repo.update_all(from(s in Setting, where: s.key == "smtp_password"),
        set: [value: "not-encrypted-with-this-key"]
      )

      assert Settings.get(:smtp_password) == ""
      refute Settings.secret_set?(:smtp_password)
    end

    @tag req: "AD-08"
    test "AD-08 invalid values are rejected and nothing is written", %{admin: admin} do
      bad = %{
        "smtp_host" => "smtp example",
        "smtp_port" => "70000",
        "smtp_security" => "ssl3",
        "mail_from" => "no-at-sign"
      }

      assert {:error, changeset} = Settings.update_settings(admin, bad)
      errors = errors_on(changeset)
      assert errors.smtp_host == ["must be a host name such as smtp.example.org"]
      assert errors.smtp_port == ["must be less than or equal to 65535"]
      assert errors.smtp_security == ["is invalid"]
      assert errors.mail_from == ["must have the @ sign and no spaces"]

      assert Audit.list_entries() == []
      assert Settings.get(:smtp_host) == ""
    end
  end

  describe "smtp_config/1" do
    defp config(overrides),
      do: Settings.all() |> Map.merge(%{smtp_host: "smtp.example.org"}) |> Map.merge(overrides)

    @tag req: "AD-08"
    test "AD-08 STARTTLS requires TLS and verifies the certificate" do
      {:ok, opts} = Mailer.smtp_config(config(%{smtp_security: "starttls"}))

      assert opts[:relay] == "smtp.example.org"
      assert opts[:port] == 587
      assert opts[:tls] == :always
      assert opts[:ssl] == false
      assert opts[:tls_options][:verify] == :verify_peer
      assert opts[:tls_options][:server_name_indication] == ~c"smtp.example.org"
    end

    @tag req: "AD-08"
    test "AD-08 TLS from the start verifies the certificate" do
      {:ok, opts} = Mailer.smtp_config(config(%{smtp_security: "tls", smtp_port: 465}))

      assert opts[:ssl] == true
      assert opts[:port] == 465
      assert opts[:sockopts][:verify] == :verify_peer
    end

    @tag req: "AD-08"
    test "AD-08 a username turns login on; none turns it off" do
      {:ok, opts} = Mailer.smtp_config(config(%{smtp_username: "u", smtp_password: "p"}))
      assert {opts[:auth], opts[:username], opts[:password]} == {:always, "u", "p"}

      {:ok, opts} = Mailer.smtp_config(config(%{smtp_username: ""}))
      assert opts[:auth] == :never
      refute opts[:password]
    end
  end

  describe "sending through SMTP" do
    setup do
      previous = Application.get_env(:idejo, Mailer)
      Application.put_env(:idejo, Mailer, adapter: Swoosh.Adapters.SMTP)
      on_exit(fn -> Application.put_env(:idejo, Mailer, previous) end)
    end

    @tag req: "AD-08"
    test "AD-08 email goes out through the SMTP server from the settings", %{admin: admin} do
      port = Idejo.SMTPCapture.start!(auth: {"forum", "s3cret-pass"})

      {:ok, _} =
        Settings.update_settings(admin, %{
          @smtp
          | "smtp_host" => "localhost",
            "smtp_port" => "#{port}",
            "smtp_security" => "none"
        })

      assert {:ok, _} = UserNotifier.deliver_test_email("ada@example.org")

      assert_receive {:smtp_mail, "forum@example.org", ["ada@example.org"], data}, 5_000
      assert data =~ "Subject: Test email from Idejo"
      assert data =~ "From: Idejo <forum@example.org>"
    end

    @tag req: "AD-08"
    test "AD-08 a wrong password is reported, not raised", %{admin: admin} do
      port = Idejo.SMTPCapture.start!(auth: {"forum", "another-pass"})

      {:ok, _} =
        Settings.update_settings(admin, %{
          @smtp
          | "smtp_host" => "localhost",
            "smtp_port" => "#{port}",
            "smtp_security" => "none"
        })

      assert {:error, _reason} = UserNotifier.deliver_test_email("ada@example.org")
      refute_received {:smtp_mail, _, _, _}
    end

    @tag req: "AD-08"
    test "AD-08 without an SMTP host nothing is sent" do
      assert {:error, :smtp_not_configured} = UserNotifier.deliver_test_email("ada@example.org")
    end
  end
end

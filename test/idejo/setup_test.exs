# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.SetupTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures
  import ExUnit.CaptureLog

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Audit
  alias Idejo.Settings
  alias Idejo.Setup

  defp owner_attrs(attrs \\ %{}), do: valid_user_attributes(attrs)

  defp settings_attrs(attrs \\ %{}) do
    Map.merge(
      %{
        "server_name" => "Lumière",
        "mail_from" => "forum@example.org",
        "smtp_host" => "smtp.example.org",
        "smtp_port" => "587",
        "smtp_security" => "starttls",
        "smtp_username" => "forum",
        "smtp_password" => "s3cret-pass"
      },
      attrs
    )
  end

  @tag req: "AD-01"
  test "AD-01 setup is needed until an owner exists" do
    assert Setup.needed?()

    # Other users, even administrators, do not count.
    user_with_role_fixture(:administrator)
    assert Setup.needed?()

    user_with_role_fixture(:owner)
    refute Setup.needed?()
  end

  @tag req: "AD-01"
  test "AD-01 the wizard creates a verified owner and saves the settings" do
    assert {:ok, owner} =
             Setup.complete(
               Setup.token(),
               owner_attrs(email: "owner@example.org"),
               settings_attrs()
             )

    assert owner.email == "owner@example.org"
    assert Accounts.confirmed?(owner)
    assert Access.administrator?(owner)
    assert "owner" in Enum.map(Access.roles_of(owner), & &1.name)
    refute Setup.needed?()

    assert Settings.get(:server_name) == "Lumière"
    assert Settings.get(:smtp_host) == "smtp.example.org"
    assert Settings.get(:smtp_password) == "s3cret-pass"
  end

  @tag req: "AD-01"
  test "AD-01 setup is audited as the owner" do
    {:ok, owner} = Setup.complete(Setup.token(), owner_attrs(), settings_attrs())

    changes = Audit.list_entries() |> Enum.map(&{&1.change, &1.admin_id}) |> Enum.sort()
    assert changes == [{"settings.update", owner.id}, {"user_role.grant", owner.id}]

    grant = Enum.find(Audit.list_entries(), &(&1.change == "user_role.grant"))
    assert grant.after == %{"user" => owner.uri, "role" => "owner"}
  end

  @tag req: "AD-01"
  test "AD-01 email can be left for later" do
    assert {:ok, _owner} =
             Setup.complete(Setup.token(), owner_attrs(), settings_attrs(%{"smtp_host" => ""}))

    assert Settings.get(:smtp_host) == ""
  end

  @tag req: "AD-01"
  test "AD-01 a wrong or missing setup code is refused and nothing is created" do
    for code <- ["wrong", "", nil, Setup.token() <> "x"] do
      assert {:error, :invalid_code} = Setup.complete(code, owner_attrs(), settings_attrs())
    end

    assert Setup.needed?()
    assert Audit.list_entries() == []
  end

  @tag req: "AD-01"
  test "AD-01 once set up, the wizard cannot create a second owner" do
    {:ok, _} = Setup.complete(Setup.token(), owner_attrs(), settings_attrs())

    assert {:error, :already_set_up} =
             Setup.complete(
               Setup.token(),
               owner_attrs(),
               settings_attrs(%{"server_name" => "Taken"})
             )

    assert Settings.get(:server_name) == "Lumière"
    assert [_one_owner] = Repo.all(Idejo.Access.UserRole)
  end

  @tag req: "AD-01"
  test "AD-01 invalid fields come back with errors and nothing is created" do
    assert {:error, %{owner: owner, settings: settings}} =
             Setup.complete(
               Setup.token(),
               owner_attrs(email: "bad", password: "short"),
               settings_attrs(%{"server_name" => " ", "smtp_port" => "0"})
             )

    assert "must have the @ sign and no spaces" in errors_on(owner).email
    assert "can't be blank" in errors_on(settings).server_name
    assert "must be greater than or equal to 1" in errors_on(settings).smtp_port

    assert {:error, %{owner: owner}} =
             Setup.complete(Setup.token(), owner_attrs(password: "short"), settings_attrs())

    assert "should be at least 12 character(s)" in errors_on(owner).password

    assert Setup.needed?()
    # Only the migrations' server account (Automessages.Defaults).
    assert Repo.all(from u in Idejo.Accounts.User, select: u.status) == ["system"]
    assert Audit.list_entries() == []
  end

  @tag req: "AD-01"
  test "AD-01 a failure after the owner is created rolls everything back" do
    # The email is unique: taken by an existing user, so registration fails late, in the
    # transaction.
    existing = unconfirmed_user_fixture()

    assert {:error, %{owner: owner}} =
             Setup.complete(Setup.token(), owner_attrs(email: existing.email), settings_attrs())

    assert "has already been taken" in errors_on(owner).email
    assert Setup.needed?()
    assert Settings.get(:server_name) == "Idejo"
  end

  @tag req: "AD-01"
  test "AD-01 the setup link with its code is written to the log while setup is needed" do
    log = capture_log(fn -> Setup.announce() end)
    assert log =~ "/setup?code=#{Setup.token()}"

    user_with_role_fixture(:owner)
    assert capture_log(fn -> Setup.announce() end) == ""
  end

  @tag req: "AD-01"
  test "AD-01 the setup code is long and random" do
    assert byte_size(Setup.token()) >= 32
    assert Setup.token() == Setup.token()
    assert Setup.valid_token?(Setup.token())
    refute Setup.valid_token?(:not_a_string)
  end
end

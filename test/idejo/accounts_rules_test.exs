# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Rules out of the web layer (AP-01 preparation): signing in, passwords and sign-up, asked
# of `Idejo.Accounts` directly. Not async: some tests turn local accounts off (AC-09).
defmodule Idejo.AccountsRulesTest do
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Accounts

  setup do
    previous = Application.get_env(:idejo, :local_accounts)

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:idejo, :local_accounts),
        else: Application.put_env(:idejo, :local_accounts, previous)
    end)

    :ok
  end

  defp passwords_off, do: Application.put_env(:idejo, :local_accounts, false)

  @tag req: "AC-01"
  test "AC-01 authenticate/2: the right password signs in; a wrong one never says which" do
    user = user_fixture()

    assert {:ok, %{id: id}} = Accounts.authenticate(user.email, valid_user_password())
    assert id == user.id
    assert {:error, :invalid} = Accounts.authenticate(user.email, "wrong password!")
    assert {:error, :invalid} = Accounts.authenticate("nobody@example.com", "whatever 123")
    assert {:error, :invalid} = Accounts.authenticate(nil, nil)
  end

  @tag req: "MO-02"
  test "MO-02 authenticate/2 tells of a ban only after the right password" do
    admin = user_with_role_fixture(:administrator)
    user = user_fixture()
    {:ok, _} = Accounts.ban_for(admin, user, :forever)

    assert {:error, {:banned, %{id: id}}} =
             Accounts.authenticate(user.email, valid_user_password())

    assert id == user.id
    assert {:error, :invalid} = Accounts.authenticate(user.email, "wrong password!")
  end

  @tag req: "AC-09"
  test "AC-09 with local accounts off, only owners and administrators use a password" do
    member = user_fixture()
    admin = user_with_role_fixture(:administrator)
    passwords_off()

    refute Accounts.password_allowed?(member)
    assert Accounts.password_allowed?(admin)
    refute Accounts.password_allowed?(nil)

    assert {:error, :invalid} = Accounts.authenticate(member.email, valid_user_password())
    assert {:ok, _} = Accounts.authenticate(admin.email, valid_user_password())

    attrs = %{"password" => "a new password!", "password_confirmation" => "a new password!"}
    assert {:error, :passwords_off} = Accounts.reset_user_password(member, attrs)
    assert {:error, :passwords_off} = Accounts.update_user_password(member, attrs, "token")
    assert {:ok, _} = Accounts.reset_user_password(admin, attrs)

    assert {:error, :passwords_off} =
             Accounts.deliver_user_reset_password_instructions(member, &"https://x/#{&1}")
  end

  @tag req: "AC-09"
  test "AC-09 register_with_password/1 is refused while accounts come only from the provider" do
    attrs = valid_user_attributes() |> Map.new(fn {k, v} -> {to_string(k), v} end)
    passwords_off()
    assert {:error, :passwords_off} = Accounts.register_with_password(attrs)

    Application.put_env(:idejo, :local_accounts, true)
    assert {:ok, _user} = Accounts.register_with_password(attrs)
  end

  @tag req: "AC-09"
  test "AC-09 may_sign_in/1: an active account not banned" do
    admin = user_with_role_fixture(:administrator)
    user = user_fixture()
    assert :ok = Accounts.may_sign_in(user)

    {:ok, {banned, _}} = Accounts.ban_for(admin, user, :forever)
    assert {:error, :banned} = Accounts.may_sign_in(banned)
    assert {:error, :inactive} = Accounts.may_sign_in(%{user_fixture() | status: "deleted"})
  end
end

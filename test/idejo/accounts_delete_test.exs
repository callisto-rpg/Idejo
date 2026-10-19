# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccountsDeleteTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Federation.Activity

  defp delete!(user) do
    {:ok, {deleted, _socket_ids}} = Accounts.delete_user(user, valid_user_password())
    deleted
  end

  @tag req: "AC-07"
  test "AC-07 deleting removes everything personal but keeps the uri" do
    user = user_with_role_fixture(:moderator, %{display_name: "Ada Lovelace"})
    deleted = delete!(user)

    stored = Repo.get!(User, user.id)
    assert stored.status == "deleted"
    assert stored.uri == user.uri
    refute stored.email == user.email
    refute stored.username == user.username
    assert stored.display_name == "Deleted user"
    assert stored.confirmed_at == nil
    assert deleted.id == user.id

    refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    assert Access.assigned_roles(stored) == []
  end

  @tag req: "AC-07"
  test "AC-07 deleting ends every session and emailed link" do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    reset =
      extract_user_token(fn url ->
        Accounts.deliver_user_reset_password_instructions(user, url)
      end)

    {:ok, {_, [_ | _]}} = Accounts.delete_user(user, valid_user_password())

    refute Accounts.get_user_by_session_token(token)
    refute Accounts.get_user_by_reset_password_token(reset)
  end

  @tag req: "AC-07"
  test "AC-07 deleting records a delete activity" do
    user = user_fixture()
    delete!(user)

    assert [%Activity{actor_uri: uri, payload: %{"type" => "Person"}}] =
             Repo.all(from a in Activity, where: a.object_uri == ^user.uri and a.verb == "delete")

    assert uri == user.uri
  end

  @tag req: "AC-07"
  test "AC-07 the email address and username can be used again" do
    user = user_fixture()
    delete!(user)

    assert {:ok, _} =
             Accounts.register_user(
               valid_user_attributes(email: user.email, username: user.username),
               skip_invite: true
             )
  end

  @tag req: "AC-07"
  test "AC-07 the password is required" do
    user = user_fixture()
    assert Accounts.delete_user(user, "not my password") == {:error, :invalid_password}
    assert Accounts.delete_user(user, nil) == {:error, :invalid_password}
    assert Repo.get!(User, user.id).status == "active"
  end

  @tag req: "AC-07"
  test "AC-07 the last owner cannot delete their account" do
    owner = user_with_role_fixture(:owner)
    assert Accounts.delete_user(owner, valid_user_password()) == {:error, :last_owner}
    assert Access.owner?(owner)

    second = user_with_role_fixture(:owner)
    assert delete!(owner).status == "deleted"
    assert Accounts.delete_user(second, valid_user_password()) == {:error, :last_owner}
  end
end

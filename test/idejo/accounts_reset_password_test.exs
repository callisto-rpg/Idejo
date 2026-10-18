# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccountsResetPasswordTest do
  use Idejo.DataCase, async: true

  import Swoosh.TestAssertions
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Accounts.{User, UserToken}

  @new_password "a brand new passphrase"

  setup do
    user = user_fixture()
    # Drain the verification email sent by the fixture.
    assert_email_sent(subject: "Verify your email address")
    %{user: user}
  end

  defp reset_token(user) do
    extract_user_token(fn url -> Accounts.deliver_user_reset_password_instructions(user, url) end)
  end

  @tag req: "AC-02"
  test "AC-02 a reset link is emailed and stored only as a hash", %{user: user} do
    token = reset_token(user)

    assert_email_sent(to: user.email, subject: "Reset your password")
    {:ok, raw} = Base.url_decode64(token, padding: false)

    assert %UserToken{context: "reset_password", sent_to: sent_to} =
             Repo.get_by(UserToken, token: :crypto.hash(:sha256, raw))

    assert sent_to == user.email
    refute Repo.get_by(UserToken, token: raw)
  end

  @tag req: "AC-02"
  test "AC-02 a valid link finds the user; a wrong or expired one does not", %{user: user} do
    token = reset_token(user)
    assert Accounts.get_user_by_reset_password_token(token).id == user.id

    refute Accounts.get_user_by_reset_password_token("oops")
    refute Accounts.get_user_by_reset_password_token(Base.url_encode64("wrong", padding: false))

    {:ok, raw} = Base.url_decode64(token, padding: false)
    offset_user_token(:crypto.hash(:sha256, raw), -25, :hour)
    refute Accounts.get_user_by_reset_password_token(token)
  end

  @tag req: "AC-02"
  test "AC-02 a link sent before the email changed no longer works", %{user: user} do
    token = reset_token(user)
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [email: "new@example.org"])
    refute Accounts.get_user_by_reset_password_token(token)
  end

  @tag req: "AC-02"
  test "AC-02 resetting sets the new password and uses the link up", %{user: user} do
    token = reset_token(user)

    assert {:ok, {_user, _socket_ids}} =
             Accounts.reset_user_password(user, %{
               password: @new_password,
               password_confirmation: @new_password
             })

    assert Accounts.get_user_by_email_and_password(user.email, @new_password)
    refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    refute Accounts.get_user_by_reset_password_token(token)
  end

  @tag req: "AC-02"
  test "AC-02 resetting ends every session of the account (SP-02)", %{user: user} do
    session_a = Accounts.generate_user_session_token(user, "socket-a")
    session_b = Accounts.generate_user_session_token(user, "socket-b")
    other = Accounts.generate_user_session_token(user_fixture(), "socket-other")

    assert {:ok, {_user, socket_ids}} =
             Accounts.reset_user_password(user, %{
               password: @new_password,
               password_confirmation: @new_password
             })

    assert Enum.sort(socket_ids) == ["socket-a", "socket-b"]
    refute Accounts.get_user_by_session_token(session_a)
    refute Accounts.get_user_by_session_token(session_b)
    assert Accounts.get_user_by_session_token(other)
    assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
  end

  @tag req: "AC-02"
  test "AC-02 a too short or mismatched password is refused", %{user: user} do
    assert {:error, changeset} =
             Accounts.reset_user_password(user, %{
               password: "short",
               password_confirmation: "nope"
             })

    assert "should be at least 12 character(s)" in errors_on(changeset).password
    assert "does not match password" in errors_on(changeset).password_confirmation
    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
  end
end

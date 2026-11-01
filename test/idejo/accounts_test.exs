# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccountsTest do
  use Idejo.DataCase, async: true

  import Swoosh.TestAssertions
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Accounts.{User, UserToken}
  alias Idejo.Federation.Activity

  describe "register_user/1" do
    @tag req: "AC-01"
    test "AC-01 signs up with email, username, display name and password" do
      email = unique_user_email()

      assert {:ok, %User{} = user} =
               Accounts.register_user(valid_user_attributes(email: email, username: "ada_l"))

      assert user.email == email
      assert user.username == "ada_l"
      assert user.display_name == "Ada Lovelace"
      assert user.status == "active"
      assert user.origin == "local"
      assert is_nil(user.password)
      refute Accounts.confirmed?(user)
    end

    @tag req: "AC-01"
    test "AC-01 hashes the password with Argon2id" do
      user = unconfirmed_user_fixture()
      assert "$argon2id$" <> _ = user.password_hash
      assert User.valid_password?(user, valid_user_password())
    end

    @tag req: "AC-01"
    test "AC-01 requires every field" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               email: ["can't be blank"],
               username: ["can't be blank"],
               display_name: ["can't be blank"],
               password: ["can't be blank"]
             } = errors_on(changeset)
    end

    @tag req: "AC-01"
    test "AC-01 validates email, username and password" do
      {:error, changeset} =
        Accounts.register_user(%{
          email: "not valid",
          username: "no spaces!",
          display_name: "   ",
          password: "short"
        })

      assert %{
               email: ["must have the @ sign and no spaces"],
               username: ["may only contain letters, digits and underscores"],
               display_name: ["can't be blank"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    @tag req: "AC-01"
    test "AC-01 validates maximum lengths for security" do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.register_user(%{email: too_long, username: too_long, password: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 30 character(s)" in errors_on(changeset).username
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    @tag req: "AC-01"
    test "AC-01 email and username are unique, ignoring case" do
      user = unconfirmed_user_fixture()

      {:error, changeset} =
        Accounts.register_user(
          valid_user_attributes(
            email: String.upcase(user.email),
            username: String.upcase(user.username)
          )
        )

      assert "has already been taken" in errors_on(changeset).email
      assert "has already been taken" in errors_on(changeset).username
    end

    @tag req: "AC-01"
    test "AC-01 FD-01 gives the user a stable URI at creation" do
      user = unconfirmed_user_fixture()
      assert user.uri == Application.fetch_env!(:idejo, :base_uri) <> "/u/" <> user.id
      assert Repo.reload!(user).uri == user.uri
    end

    @tag req: "AC-01"
    test "AC-01 FD-02 records a create activity" do
      user = unconfirmed_user_fixture()

      assert [%Activity{verb: "create", actor_uri: uri, object_uri: uri, payload: payload}] =
               Repo.all(from a in Activity, where: a.object_uri == ^user.uri)

      assert uri == user.uri
      assert payload == %{"type" => "Person", "username" => user.username}
    end

    @tag req: "AC-01"
    test "AC-01 FD-02 writes no activity when sign-up fails" do
      # The migrations' server account (Automessages.Defaults) has one already.
      before = Repo.aggregate(Activity, :count)
      {:error, _} = Accounts.register_user(%{})
      assert Repo.aggregate(Activity, :count) == before
    end
  end

  describe "get_user_by_email_and_password/2" do
    @tag req: "AC-01"
    test "AC-01 returns the user if the email and password are valid" do
      %{id: id} = user = unconfirmed_user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    @tag req: "AC-01"
    test "AC-01 does not return the user if the password is not valid" do
      user = unconfirmed_user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    @tag req: "AC-01"
    test "AC-01 does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    @tag req: "AC-01"
    test "AC-01 emails a verification link", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"

      assert_email_sent(to: user.email, subject: "Verify your email address")
    end

    @tag req: "AC-01"
    test "AC-01 sends nothing once the address is verified" do
      user = user_fixture()

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(user, & &1)
    end
  end

  describe "confirm_user/1" do
    setup do
      user = unconfirmed_user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    @tag req: "AC-01"
    test "AC-01 verifies the email address with a valid token", %{user: user, token: token} do
      assert {:ok, confirmed} = Accounts.confirm_user(token)
      assert confirmed.id == user.id
      assert Accounts.confirmed?(confirmed)
      assert Accounts.confirmed?(Repo.reload!(user))
    end

    @tag req: "AC-01"
    test "AC-01 a verification token works only once", %{token: token} do
      assert {:ok, _} = Accounts.confirm_user(token)
      assert {:error, :invalid_token} = Accounts.confirm_user(token)
      refute Repo.get_by(UserToken, context: "confirm")
    end

    @tag req: "AC-01"
    test "AC-01 rejects an invalid token", %{user: user} do
      assert {:error, :invalid_token} = Accounts.confirm_user("oops")
      assert {:error, :invalid_token} = Accounts.confirm_user(Base.url_encode64("not-it"))
      refute Accounts.confirmed?(Repo.reload!(user))
    end

    @tag req: "AC-01"
    test "AC-01 rejects an expired token", %{user: user, token: token} do
      {:ok, decoded} = Base.url_decode64(token, padding: false)
      offset_user_token(:crypto.hash(:sha256, decoded), -8, :day)

      assert {:error, :invalid_token} = Accounts.confirm_user(token)
      refute Accounts.confirmed?(Repo.reload!(user))
    end

    @tag req: "AC-01"
    test "AC-01 rejects a token sent to an earlier email address", %{user: user, token: token} do
      Repo.update_all(from(u in User, where: u.id == ^user.id), set: [email: "new@example.com"])
      assert {:error, :invalid_token} = Accounts.confirm_user(token)
    end
  end

  describe "session tokens" do
    setup do
      user = user_fixture()
      %{user: user, token: Accounts.generate_user_session_token(user)}
    end

    @tag req: "AC-01"
    test "AC-01 returns the user by session token", %{user: user, token: token} do
      assert {session_user, inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert %DateTime{} = inserted_at
    end

    @tag req: "AC-01"
    test "AC-01 session tokens expire after 14 days", %{token: token} do
      offset_user_token(token, -15, :day)
      refute Accounts.get_user_by_session_token(token)
    end

    @tag req: "AC-01"
    test "AC-01 signing out deletes the session token", %{token: token} do
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end

    @tag req: "AC-01"
    test "AC-01 rejects an unknown session token" do
      refute Accounts.get_user_by_session_token("oops")
    end
  end

  describe "inspect/2 for the User module" do
    @tag req: "AC-01"
    test "AC-01 does not include the password or its hash" do
      inspected = inspect(%User{password: "123456", password_hash: "$argon2id$x"})
      refute inspected =~ "123456"
      refute inspected =~ "argon2id"
    end
  end
end

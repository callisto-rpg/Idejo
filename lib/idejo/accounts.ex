# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts do
  @moduledoc """
  Accounts: sign-up with email verification (AC-01) and sessions.
  """

  import Ecto.Query, warn: false
  alias Idejo.Federation
  alias Idejo.Repo

  alias Idejo.Accounts.{User, UserNotifier, UserToken}

  ## Database getters

  @doc """
  Gets a user by email and password. Returns `nil` if either is wrong.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user. Raises `Ecto.NoResultsError` if the user does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  ## Sign-up

  @doc """
  Signs up a user with email, username, display name and password.

  The account is created with a stable URI (FD-01) and a `create` activity (FD-02) in one
  transaction. The email address is not verified yet; see
  `deliver_user_confirmation_instructions/2`.
  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    id = Federation.generate_id()
    uri = Federation.uri(:user, id)

    Repo.transact(fn ->
      with {:ok, user} <-
             Repo.insert(User.registration_changeset(%User{id: id, uri: uri}, attrs)),
           {:ok, _activity} <-
             Repo.insert(
               Federation.activity_changeset(%{
                 actor_uri: user.uri,
                 verb: "create",
                 object_uri: user.uri,
                 payload: %{"type" => "Person", "username" => user.username}
               })
             ) do
        {:ok, user}
      end
    end)
  end

  @doc """
  Returns a changeset for the sign-up form.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  ## Email verification

  @doc """
  Returns true once the user has verified their email address.
  """
  @spec confirmed?(User.t()) :: boolean()
  def confirmed?(%User{confirmed_at: confirmed_at}), do: not is_nil(confirmed_at)

  @doc """
  Emails a verification link to a user who has not verified their address yet.

  `confirm_url_fun` receives the encoded token and returns the link.
  """
  def deliver_user_confirmation_instructions(%User{} = user, confirm_url_fun)
      when is_function(confirm_url_fun, 1) do
    if confirmed?(user) do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirm_url_fun.(encoded_token))
    end
  end

  @doc """
  Verifies the user's email address with the token from the email.

  The token is single-use: all verification tokens of the user are deleted.
  """
  @spec confirm_user(String.t()) :: {:ok, User.t()} | {:error, :invalid_token}
  def confirm_user(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_confirm_token_query(token),
         {user, _token} <- Repo.one(query) do
      Repo.transact(fn -> confirm_and_delete_tokens(user) end)
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp confirm_and_delete_tokens(user) do
    with {:ok, user} <- Repo.update(User.confirm_changeset(user)) do
      Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: "confirm"]))
      {:ok, user}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end
end

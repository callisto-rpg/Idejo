# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccountsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Idejo.Accounts` context.
  """

  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def unique_username, do: "user_#{System.unique_integer([:positive])}"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      username: unique_username(),
      display_name: "Ada Lovelace",
      password: valid_user_password()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_confirmation_instructions(user, url)
      end)

    {:ok, user} = Accounts.confirm_user(token)
    user
  end

  @doc "A verified user holding the given built-in role, e.g. `:administrator`."
  def user_with_role_fixture(role, attrs \\ %{}) do
    user = user_fixture(attrs)
    :ok = Idejo.Access.grant_role(user, Idejo.Access.built_in_role!(role))
    user
  end

  def user_scope_fixture(user \\ user_fixture()), do: Scope.for_user(user)

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Idejo.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt]
    )
  end
end

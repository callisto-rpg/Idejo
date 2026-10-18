# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.UserToken do
  @moduledoc """
  Session tokens and emailed tokens (email verification, password reset).
  """
  use Ecto.Schema
  import Ecto.Query
  alias Idejo.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  @confirm_validity_in_days 7
  # Short, since whoever holds the link can set a new password.
  @reset_password_validity_in_days 1
  @session_validity_in_days 14

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    # Session tokens only: the browser session's live socket id (see IdejoWeb.UserAuth).
    field :socket_id, :string
    belongs_to :user, Idejo.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  Session tokens are stored in the database, not only in the signed cookie, so that
  individual sessions can be expired.
  """
  def build_session_token(user, socket_id) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {token, %UserToken{token: token, context: "session", user_id: user.id, socket_id: socket_id}}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any, along with the token's creation time.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {user, token.inserted_at}

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  The non-hashed token is sent to the user email while the hashed part is stored in the
  database, so anyone with read-only access to the database cannot use it. A token is
  only valid for the address it was sent to.
  """
  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  Checks if an emailed token is valid and returns its lookup query.

  If found, the query returns a tuple of the form `{user, token}`. The token must match its
  hashed counterpart, be younger than its context allows and have been sent to the user's
  current email. Contexts: `"confirm"` (7 days) and `"reset_password"` (1 day).
  """
  def verify_email_token_query(token, context) when context in ["confirm", "reset_password"] do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^validity_in_days(context), "day"),
            where: token.sent_to == user.email,
            select: {user, token}

        {:ok, query}

      :error ->
        :error
    end
  end

  defp validity_in_days("confirm"), do: @confirm_validity_in_days
  defp validity_in_days("reset_password"), do: @reset_password_validity_in_days

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end

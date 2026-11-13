# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.ApiTokens do
  @moduledoc """
  Sign-in for the official app (AP-08 to AP-10, AP-20; steward decision, 2026-11-10).

  There is one client, built in: `#{"org.idejo.app"}`, whose only redirect is
  `org.idejo.app:/oauth/callback` (RFC 8252, a private-use scheme). No other client, no
  registration, no personal tokens.

    * `check_request/1` checks an authorization request (the authorize page asks it before
      showing anything, and refuses without redirecting on any doubt);
    * `create_code/2` makes the one-minute code once the signed-in person allows it;
    * `exchange/1` turns a code into a device token (PKCE S256, single use; a reused code
      revokes the token it gave, RFC 6749 §4.1.2);
    * `authenticate/1` finds the user of a `Bearer` token, with the same rules as a browser
      session: an active account, not banned (`Accounts.may_sign_in/1`);
    * `revoke/2`, `revoke_all_in_transaction/1` and `announce_revoked/2` end tokens: the
      app's sign-out, Remove in Profile and account, password reset and change, ban,
      account deletion and leaving the provider.

  Codes and tokens are 32 random bytes; only their SHA-256 hashes are stored. Tokens read
  `idj_` and the bytes in URL-safe Base64.

  A revoked token's sockets are disconnected and its UnifiedPush registrations deleted
  (`push_subscriptions.api_token_id`, deleted with it by the database). Events go to
  `"api_tokens"` on `Idejo.PubSub`: `{:api_tokens_revoked, user_id, ids}`, and to
  `"api_token:{id}"`: `{:api_token_revoked, id}`.

  Changes to this module get an extra careful human review (DV-06).
  """
  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.{ApiCode, ApiToken, User}
  alias Idejo.Repo
  alias Idejo.Settings

  @client_id "org.idejo.app"
  @redirect_uri "org.idejo.app:/oauth/callback"
  @scopes ~w(read write private moderate push)
  @max_live 20
  @code_seconds 60
  @touch_seconds 3600
  @prefix "idj_"
  @pubsub Idejo.PubSub

  @type request :: %{
          scopes: [String.t()],
          state: String.t() | nil,
          challenge: String.t(),
          device_name: String.t()
        }

  @doc "The official app's client id, the only one."
  @spec client_id() :: String.t()
  def client_id, do: @client_id

  @doc "The official app's redirect, the only one."
  @spec redirect_uri() :: String.t()
  def redirect_uri, do: @redirect_uri

  @doc "Every scope, in the order the app asks for them (AP-10)."
  @spec scopes() :: [String.t()]
  def scopes, do: @scopes

  @doc "How many live tokens one user keeps; a new one past it revokes the oldest."
  @spec max_live() :: pos_integer()
  def max_live, do: @max_live

  @doc """
  Whether the API and the app's sign-in are on (AP-20): the "API and mobile app" setting.
  Off, tokens are kept but refused.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: Settings.get(:api_enabled) == true

  @doc """
  Checks an authorization request's parameters (AP-08): `response_type` `code`, the fixed
  client id and redirect, a PKCE challenge with `S256`, known scopes, an optional `state` and
  `device_name`. Returns what the code will be bound to, or why it is refused. Nothing here
  may lead to a redirect: a request that fails is shown as an error page.
  """
  @spec check_request(map()) ::
          {:ok, request()}
          | {:error,
             :invalid_client
             | :invalid_redirect
             | :unsupported_response_type
             | :invalid_challenge
             | :invalid_scope}
  def check_request(params) when is_map(params) do
    cond do
      params["client_id"] != @client_id -> {:error, :invalid_client}
      params["redirect_uri"] != @redirect_uri -> {:error, :invalid_redirect}
      params["response_type"] != "code" -> {:error, :unsupported_response_type}
      params["code_challenge_method"] != "S256" -> {:error, :invalid_challenge}
      not challenge?(params["code_challenge"]) -> {:error, :invalid_challenge}
      true -> with {:ok, scopes} <- parse_scopes(params["scope"]), do: request(params, scopes)
    end
  end

  defp request(params, scopes) do
    {:ok,
     %{
       scopes: scopes,
       state: if(is_binary(params["state"]), do: String.slice(params["state"], 0, 500)),
       challenge: params["code_challenge"],
       device_name: device_name(params["device_name"])
     }}
  end

  # RFC 7636: BASE64URL(SHA256(verifier)), 43 characters without padding.
  defp challenge?(challenge) when is_binary(challenge),
    do: Regex.match?(~r/\A[A-Za-z0-9_-]{43}\z/, challenge)

  defp challenge?(_challenge), do: false

  # RFC 7636 §4.1: 43 to 128 unreserved characters.
  defp verifier?(verifier) when is_binary(verifier),
    do: Regex.match?(~r/\A[A-Za-z0-9._~-]{43,128}\z/, verifier)

  defp verifier?(_verifier), do: false

  defp parse_scopes(scope) when is_binary(scope) do
    case String.split(scope, " ", trim: true) do
      [] ->
        {:error, :invalid_scope}

      asked ->
        if Enum.all?(asked, &(&1 in @scopes)),
          do: {:ok, Enum.filter(@scopes, &(&1 in asked))},
          else: {:error, :invalid_scope}
    end
  end

  # No scope asked: everything, as the app asks for (AP-10).
  defp parse_scopes(nil), do: {:ok, @scopes}
  defp parse_scopes(_scope), do: {:error, :invalid_scope}

  @doc """
  The name a device is listed under: what the app sent, trimmed, without control
  characters, at most 64 characters; "idejo app" when it sent none.
  """
  @spec device_name(term()) :: String.t()
  def device_name(name) when is_binary(name) do
    case name |> String.replace(~r/[[:cntrl:]]/u, "") |> String.trim() |> String.slice(0, 64) do
      "" -> "idejo app"
      name -> name
    end
  end

  def device_name(_name), do: "idejo app"

  @doc """
  Makes the authorization code for `user`, who allowed the app on the confirmation page
  (AP-08). Refused while the API is off (`:disabled`) or when the account may not sign in
  (`Accounts.may_sign_in/1`). Returns the code itself, shown once in the redirect.
  """
  @spec create_code(User.t(), request()) ::
          {:ok, String.t()} | {:error, :disabled | :banned | :inactive}
  def create_code(%User{} = user, %{challenge: challenge} = request) do
    with :ok <- if(enabled?(), do: :ok, else: {:error, :disabled}),
         :ok <- Accounts.may_sign_in(user) do
      code = random()

      Repo.insert!(%ApiCode{
        user_id: user.id,
        code_hash: hash(code),
        challenge: challenge,
        scopes: request.scopes,
        device_name: request.device_name,
        expires_at: DateTime.add(DateTime.utc_now(), @code_seconds, :second)
      })

      {:ok, code}
    end
  end

  @doc """
  Exchanges an authorization code for a device token (AP-08, AP-09). `params` is the token
  request: `grant_type` `authorization_code`, `code`, `redirect_uri`, `client_id`,
  `code_verifier`. Everything is checked; a code used before revokes the token it gave and
  is refused. Returns the token itself (shown once), its row and its user.
  """
  @spec exchange(map()) ::
          {:ok, String.t(), ApiToken.t(), User.t()}
          | {:error,
             :unsupported_grant_type
             | :invalid_request
             | :invalid_client
             | :invalid_grant
             | :disabled}
  def exchange(params) when is_map(params) do
    cond do
      not enabled?() ->
        {:error, :disabled}

      params["grant_type"] != "authorization_code" ->
        {:error, :unsupported_grant_type}

      params["client_id"] != @client_id ->
        {:error, :invalid_client}

      not is_binary(params["code"]) or not verifier?(params["code_verifier"]) ->
        {:error, :invalid_request}

      params["redirect_uri"] != @redirect_uri ->
        {:error, :invalid_grant}

      true ->
        redeem(params["code"], params["code_verifier"])
    end
  end

  defp redeem(code, verifier) do
    result =
      Repo.transact(fn ->
        found =
          Repo.one(
            from c in ApiCode, where: c.code_hash == ^hash(code), lock: "FOR UPDATE", limit: 1
          )

        check_code(found, verifier, DateTime.utc_now())
      end)

    case result do
      # RFC 6749 §4.1.2: a code used twice was stolen or replayed; its token goes too.
      {:ok, {:reused, code}} ->
        if code.token_id, do: revoke_ids(code.user_id, [code.token_id])
        {:error, :invalid_grant}

      {:ok, {token, row, user, revoked}} ->
        announce_revoked(user.id, revoked)
        {:ok, token, row, user}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_code(nil, _verifier, _now), do: {:error, :invalid_grant}

  defp check_code(%ApiCode{used_at: %DateTime{}} = code, _verifier, _now),
    do: {:ok, {:reused, code}}

  defp check_code(code, verifier, now) do
    cond do
      DateTime.after?(now, code.expires_at) -> {:error, :invalid_grant}
      not pkce?(verifier, code.challenge) -> {:error, :invalid_grant}
      true -> issue(code, now)
    end
  end

  defp pkce?(verifier, challenge) do
    computed = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    Plug.Crypto.secure_compare(computed, challenge)
  end

  defp issue(code, now) do
    user = Repo.get!(User, code.user_id)

    with :ok <- Accounts.may_sign_in(user) |> sign_in_result() do
      token = @prefix <> random()

      row =
        Repo.insert!(%ApiToken{
          user_id: user.id,
          name: code.device_name,
          scopes: code.scopes,
          token_hash: hash(token)
        })

      Repo.update_all(from(c in ApiCode, where: c.id == ^code.id),
        set: [used_at: now, token_id: row.id]
      )

      {:ok, {token, row, user, revoke_past_limit(user.id)}}
    end
  end

  defp sign_in_result(:ok), do: :ok
  defp sign_in_result({:error, _}), do: {:error, :invalid_grant}

  # A 21st live token revokes the oldest.
  defp revoke_past_limit(user_id) do
    keep =
      from t in ApiToken,
        where: t.user_id == ^user_id and is_nil(t.revoked_at),
        order_by: [desc: t.inserted_at, desc: t.id],
        limit: @max_live,
        select: t.id

    {_, ids} =
      Repo.update_all(
        from(t in ApiToken,
          where: t.user_id == ^user_id and is_nil(t.revoked_at) and t.id not in subquery(keep),
          select: t.id
        ),
        set: [revoked_at: DateTime.utc_now()]
      )

    delete_registrations(ids)
    ids
  end

  @doc """
  The user of a `Bearer` token and its row (AP-09, AP-10): the token live, the API on, the
  account active and not banned. A ban for good is `:banned`, one with an end `:suspended`,
  so the app can say which. `last_used_at` moves at most once an hour.
  """
  @spec authenticate(String.t() | nil) ::
          {:ok, User.t(), ApiToken.t()}
          | {:error, :invalid | :disabled | :banned | :suspended}
  def authenticate(@prefix <> _ = token) do
    found =
      Repo.one(
        from t in ApiToken,
          join: u in assoc(t, :user),
          where: t.token_hash == ^hash(token) and is_nil(t.revoked_at),
          select: {t, u}
      )

    case found do
      nil -> {:error, :invalid}
      {row, user} -> check_user(row, user)
    end
  end

  def authenticate(_token), do: {:error, :invalid}

  defp check_user(row, user) do
    cond do
      not enabled?() -> {:error, :disabled}
      user.status != "active" -> {:error, :invalid}
      Accounts.banned?(user) and is_nil(user.banned_until) -> {:error, :banned}
      Accounts.banned?(user) -> {:error, :suspended}
      true -> {:ok, Accounts.seen(user), touch(row)}
    end
  end

  defp touch(%ApiToken{last_used_at: last} = row) do
    now = DateTime.utc_now()

    if last && DateTime.diff(now, last) < @touch_seconds do
      row
    else
      Repo.update_all(from(t in ApiToken, where: t.id == ^row.id), set: [last_used_at: now])
      %{row | last_used_at: now}
    end
  end

  @doc "The user's live tokens, newest first (Profile and account, \"Apps and devices\")."
  @spec list(User.t()) :: [ApiToken.t()]
  def list(%User{id: user_id}) do
    Repo.all(
      from t in ApiToken,
        where: t.user_id == ^user_id and is_nil(t.revoked_at),
        order_by: [desc: t.inserted_at, desc: t.id]
    )
  end

  @doc """
  Revokes one of the user's tokens (Remove in Profile and account, or the app's own
  sign-out). `{:error, :not_found}` for an id that is not a live token of theirs.
  """
  @spec revoke(User.t(), String.t()) :: :ok | {:error, :not_found}
  def revoke(%User{id: user_id}, id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         [_] <- revoke_ids(user_id, [uuid]) do
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Revokes the token given as a string (RFC 7009); unknown tokens change nothing."
  @spec revoke_by_token(String.t() | nil) :: :ok
  def revoke_by_token(@prefix <> _ = token) do
    case Repo.one(
           from t in ApiToken,
             where: t.token_hash == ^hash(token) and is_nil(t.revoked_at),
             select: {t.id, t.user_id}
         ) do
      {id, user_id} -> revoke_ids(user_id, [id])
      nil -> []
    end

    :ok
  end

  def revoke_by_token(_token), do: :ok

  defp revoke_ids(user_id, ids) do
    {_, revoked} =
      Repo.update_all(
        from(t in ApiToken,
          where: t.user_id == ^user_id and t.id in ^ids and is_nil(t.revoked_at),
          select: t.id
        ),
        set: [revoked_at: DateTime.utc_now()]
      )

    delete_registrations(revoked)
    announce_revoked(user_id, revoked)
    revoked
  end

  @doc """
  Revokes every live token of `user`, inside the caller's transaction (password reset and
  change, ban, account deletion, leaving the provider). Returns their ids; call
  `announce_revoked/2` with them once the transaction has committed, so their sockets end.
  """
  @spec revoke_all_in_transaction(User.t()) :: [Ecto.UUID.t()]
  def revoke_all_in_transaction(%User{id: user_id}) do
    {_, ids} =
      Repo.update_all(
        from(t in ApiToken, where: t.user_id == ^user_id and is_nil(t.revoked_at), select: t.id),
        set: [revoked_at: DateTime.utc_now()]
      )

    delete_registrations(ids)
    ids
  end

  # AP-19, PN-13: an app's push registrations end with its token.
  defp delete_registrations([]), do: :ok

  defp delete_registrations(ids) do
    Repo.delete_all(from s in Idejo.Push.Subscription, where: s.api_token_id in ^ids)
    :ok
  end

  @doc """
  Tells the token's channels (`"api_token:{id}"`: `{:api_token_revoked, id}`, so the app
  hears `token.revoked`) and the web layer (`"api_tokens"`: `{:api_tokens_revoked, user_id,
  ids}`, which disconnects their sockets) that tokens ended.
  """
  @spec announce_revoked(Ecto.UUID.t(), [Ecto.UUID.t()]) :: :ok
  def announce_revoked(_user_id, []), do: :ok

  def announce_revoked(user_id, ids) do
    for id <- ids,
        do: Phoenix.PubSub.broadcast(@pubsub, "api_token:" <> id, {:api_token_revoked, id})

    Phoenix.PubSub.broadcast(@pubsub, "api_tokens", {:api_tokens_revoked, user_id, ids})
    :ok
  end

  @doc """
  The API was just switched off (AP-20): every live token's sockets end. Tokens are kept,
  so they work again once it is on. Sends `{:api_disabled, ids}` on `"api_tokens"`, from the
  caller's process (the settings' save), so the listener does no database work.
  """
  @spec announce_disabled() :: :ok
  def announce_disabled do
    ids = Repo.all(from t in ApiToken, where: is_nil(t.revoked_at), select: t.id)
    Phoenix.PubSub.broadcast(@pubsub, "api_tokens", {:api_disabled, ids})
  end

  @doc "Whether `scope` is among the token's (AP-10)."
  @spec scope?(ApiToken.t(), String.t()) :: boolean()
  def scope?(%ApiToken{scopes: scopes}, scope), do: scope in scopes

  defp random, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  defp hash(value), do: :crypto.hash(:sha256, value)
end

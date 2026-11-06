# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.OIDC do
  @moduledoc """
  Sign-in through one OpenID Connect provider (AC-09), set by the environment
  (`IDEJO_OIDC_*`, read by `config/runtime.exs` into `config :idejo, :oidc`) or, without it,
  connected from the admin panel (`Idejo.Accounts.OIDCRegistry`; steward decisions,
  2026-11-06). `config/0` is the one place either is read.

  The protocol is `oidcc`'s (Apache-2.0): the provider's settings are discovered from its
  `/.well-known/openid-configuration` and kept fresh by a worker started with the app
  (`child_specs/0`); the authorization code flow uses PKCE (S256), `state` and `nonce`
  (`new_request/0`, kept by the web layer in the encrypted session, single-use, for
  #{div(600, 60)} minutes); the ID token's signature, `iss`, `aud`, `exp`, `iat` and `nonce`
  are checked by `Oidcc.retrieve_token/5`.

  Accounts are linked by the provider's issuer and subject (`Idejo.Accounts.UserIdentity`),
  never by email. A first sign-in makes a local member under the registration mode, like a
  sign-up; an existing account with the same email is never linked by itself (steward
  decision, 2026-11-02): its owner signs in with their password and links it from their
  profile (`link/2`). The provider never grants a role: no claim but `sub`, `email`,
  `email_verified`, `name` and `preferred_username` is read.
  """
  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.{OIDCRegistry, User, UserIdentity}
  alias Idejo.Community.Profile
  alias Idejo.Repo
  alias Oidcc.ProviderConfiguration.Worker

  @provider __MODULE__.Provider
  @scopes ["openid", "email", "profile"]
  # How long a sign-in may take at the provider, and how fresh a sign-in confirming an
  # account's deletion must be (steward decision, 2026-11-02).
  @request_seconds 600
  @reauth_seconds 300

  @typedoc "What the web layer keeps between the redirect and the callback."
  @type request :: %{String.t() => String.t() | integer()}

  ## Configuration

  @doc "Whether sign-in through OpenID Connect is set up."
  @spec enabled?() :: boolean()
  def enabled?, do: config() != nil

  @doc """
  The provider's settings (`issuer`, `client_id`, `client_secret`, `label`): the
  environment's, else the admin panel's connection, else nil.
  """
  @spec config() :: keyword() | nil
  def config, do: Application.get_env(:idejo, :oidc) || OIDCRegistry.config()

  @doc """
  Where people without an account at the provider make one (`IDEJO_OIDC_SIGN_UP_URL`; steward
  decision, 2026-11-06), or nil. Only with the provider set up.
  """
  @spec sign_up_url() :: String.t() | nil
  def sign_up_url,
    do: if(enabled?(), do: Application.get_env(:idejo, :oidc_sign_up_url) || config(:sign_up_url))

  @doc "The sign-in button's provider name (`IDEJO_OIDC_LABEL`)."
  @spec label() :: String.t() | nil
  def label, do: config(:label)

  @doc """
  Whether people sign in, sign up and reset passwords with a password here
  (`IDEJO_LOCAL_ACCOUNTS`, on by default). Off, only OpenID Connect is offered, except to
  owners and administrators, who keep a password sign-in so the command line can always
  let them in (AD-09).
  """
  @spec local_accounts?() :: boolean()
  def local_accounts?, do: Application.get_env(:idejo, :local_accounts, true)

  @doc "The provider worker to start with the app, when sign-in through it is set up."
  @spec child_specs() :: [Supervisor.child_spec() | {module(), term()}]
  def child_specs do
    # The admin panel's connection is started by `OIDCRegistry` once the repo runs.
    case Application.get_env(:idejo, :oidc) do
      nil -> []
      oidc -> worker_specs(oidc)
    end
  end

  @doc false
  def worker_specs(oidc) do
    if oidc do
      [
        {Worker,
         %{
           issuer: oidc[:issuer],
           name: @provider,
           # A provider down at boot is asked again, never stopping the app.
           backoff_type: :random_exponential,
           backoff_min: 1_000,
           backoff_max: 300_000
         }}
      ]
    else
      []
    end
  end

  @doc "The name of the provider worker (tests start their own under it)."
  @spec provider() :: atom()
  def provider, do: @provider

  defp config(key), do: (config() || [])[key]

  ## The flow

  @doc """
  A new sign-in request: random `state`, `nonce` and PKCE verifier, with the time it was
  made, `intent` (`"sign_in"`, `"link"` or `"reauth"`) and the invite code to carry.
  """
  @spec new_request(String.t(), String.t() | nil) :: request()
  def new_request(intent, invite \\ nil) do
    %{
      "state" => random(32),
      "nonce" => random(32),
      "verifier" => random(48),
      "intent" => intent,
      "invite" => invite,
      "at" => System.system_time(:second)
    }
  end

  defp random(bytes), do: Base.url_encode64(:crypto.strong_rand_bytes(bytes), padding: false)

  @doc """
  The provider's address to send the browser to. A `"reauth"` request asks the provider to
  sign the person in again (`prompt=login`, `max_age=0`).
  """
  @spec authorize_url(request(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def authorize_url(request, redirect_uri) do
    extension =
      if request["intent"] == "reauth", do: [{"prompt", "login"}, {"max_age", "0"}], else: []

    with {:ok, url} <-
           Oidcc.create_redirect_url(@provider, config(:client_id), config(:client_secret), %{
             redirect_uri: redirect_uri,
             state: request["state"],
             nonce: request["nonce"],
             pkce_verifier: request["verifier"],
             require_pkce: true,
             scopes: @scopes,
             url_extension: extension
           }) do
      {:ok, IO.iodata_to_binary(url)}
    end
  end

  @doc """
  The checked claims of the ID token for `code`, when the callback's `state` is the
  request's and the request is fresh. Every failure is `{:error, reason}`: the reason is
  for the log only, never shown.
  """
  @spec claims(request() | nil, map(), String.t()) :: {:ok, map()} | {:error, term()}
  def claims(nil, _params, _redirect_uri), do: {:error, :no_request}

  def claims(request, %{"state" => state, "code" => code}, redirect_uri)
      when is_binary(state) and is_binary(code) do
    cond do
      not Plug.Crypto.secure_compare(state, request["state"] || "") ->
        {:error, :state}

      System.system_time(:second) - (request["at"] || 0) > @request_seconds ->
        {:error, :expired}

      true ->
        retrieve(code, request, redirect_uri)
    end
  end

  def claims(_request, %{"error" => error}, _redirect_uri), do: {:error, {:provider, error}}
  def claims(_request, _params, _redirect_uri), do: {:error, :no_code}

  defp retrieve(code, request, redirect_uri) do
    case Oidcc.retrieve_token(code, @provider, config(:client_id), config(:client_secret), %{
           redirect_uri: redirect_uri,
           nonce: request["nonce"],
           pkce_verifier: request["verifier"],
           # oidcc asks the worker for new keys itself when a token names an unknown one.
           require_pkce: true
         }) do
      {:ok, %Oidcc.Token{id: %Oidcc.Token.Id{claims: %{"sub" => sub} = claims}}}
      when is_binary(sub) and sub != "" ->
        {:ok, claims}

      {:ok, _token} ->
        {:error, :no_subject}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Whether a re-authentication made at `at` (Unix seconds) still confirms a deletion."
  @spec fresh_reauth?(integer() | nil) :: boolean()
  def fresh_reauth?(at) when is_integer(at),
    do: System.system_time(:second) - at <= @reauth_seconds

  def fresh_reauth?(_at), do: false

  ## Accounts

  @doc "The account linked to these claims' issuer and subject, or nil."
  @spec find_user(map()) :: User.t() | nil
  def find_user(%{"iss" => issuer, "sub" => subject}) do
    Repo.one(
      from u in User,
        join: i in UserIdentity,
        on: i.user_id == u.id,
        where: i.issuer == ^issuer and i.subject == ^subject
    )
  end

  @doc """
  Signs a person in from checked claims: the linked account, or a new member made under the
  registration mode (an invite code when invite-only; none while closed). Their email is
  verified only when the provider says so (`email_verified`); otherwise Idejo's own
  verification email follows (AC-01), sent by the web layer for `{:ok, user, :unverified}`.

  Errors: `:no_email` (the provider gave none), `:email_taken` (an account here has that
  email: never linked by itself), `:closed`, `:invite`, or a changeset.
  """
  @spec sign_in(map(), String.t() | nil) ::
          {:ok, User.t(), :existing | :new | :unverified}
          | {:error, :no_email | :email_taken | :closed | :invite | Ecto.Changeset.t()}
  def sign_in(claims, invite_code \\ nil) do
    case find_user(claims) do
      %User{} = user -> {:ok, user, :existing}
      nil -> create(claims, invite_code)
    end
  end

  @doc """
  Whether a person the provider vouches for, not yet linked here, may be asked to join:
  `:ok`, or the error `sign_in/2` would give (`:no_email`, `:email_taken`, `:closed`), so
  nobody consents only to be refused. An invite is checked when they join.
  """
  @spec precheck(map()) :: :ok | {:error, :no_email | :email_taken | :closed}
  def precheck(claims) do
    with {:ok, email} <- email(claims) do
      cond do
        Accounts.get_user_by_email(email) -> {:error, :email_taken}
        not Accounts.sign_ups_open?() -> {:error, :closed}
        true -> :ok
      end
    end
  end

  @consent_claims ~w(iss sub email email_verified name preferred_username)

  @doc """
  The claims kept while a person decides whether to join (the consent page): what
  `sign_in/2` reads and nothing else.
  """
  def consent_claims(claims), do: Map.take(claims, @consent_claims)

  @doc "What the consent page shows: the email and the display name a new member would get."
  def consent_details(claims) do
    {:ok, email} = email(claims)
    %{email: email, display_name: display_name(claims)}
  end

  defp create(claims, invite_code) do
    with {:ok, email} <- email(claims) do
      if Accounts.get_user_by_email(email),
        do: {:error, :email_taken},
        else: register(claims, email, invite_code)
    end
  end

  defp email(%{"email" => email}) when is_binary(email) and email != "",
    do: {:ok, String.trim(email)}

  defp email(_claims), do: {:error, :no_email}

  # Never from the email, in any part: a username and a display name are public (steward
  # report, 2026-11-06: providers may give the email as `preferred_username`).
  defp register(claims, email, invite_code) do
    verified? = claims["email_verified"] in [true, "true"]
    name = display_name(claims)
    # The provider's public profile, where it keeps one (Idejo.Community.Profile).
    profile = Profile.fetch(claims["sub"])

    attrs = %{
      "email" => email,
      "username" =>
        Accounts.free_username(
          (profile && profile.username) || public(claims["preferred_username"]) ||
            public(claims["name"])
        ),
      "display_name" => name,
      # Nobody knows it: the provider signs them in. "Forgot your password?" can set one.
      "password" => random(32),
      "invite_code" => invite_code
    }

    Repo.transact(fn ->
      with {:ok, user} <- Accounts.register_user(attrs, confirmed: verified?),
           {:ok, _identity} <- insert_identity(user, claims) do
        {:ok, user}
      end
    end)
    |> case do
      {:ok, user} ->
        Profile.adopt_picture(user, profile)
        {:ok, Repo.get!(User, user.id), if(verified?, do: :new, else: :unverified)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, registration_error(changeset)}
    end
  end

  defp display_name(claims) do
    (public(claims["name"]) || public(claims["preferred_username"]) || "Member")
    |> String.slice(0, 60)
  end

  # A claim fit to show others: text, and nothing that looks like an email address.
  defp public(value) when is_binary(value) do
    value = String.trim(value)
    if value != "" and not String.contains?(value, "@"), do: value
  end

  defp public(_value), do: nil

  defp registration_error(%Ecto.Changeset{errors: errors} = changeset) do
    cond do
      {"cannot sign up: sign-ups are closed", []} in Keyword.get_values(errors, :email) -> :closed
      Keyword.has_key?(errors, :invite_code) -> :invite
      true -> changeset
    end
  end

  defp insert_identity(user, %{"iss" => issuer, "sub" => subject}) do
    %{user_id: user.id, issuer: issuer, subject: subject}
    |> UserIdentity.changeset()
    |> Repo.insert()
  end

  @doc """
  Links the signed-in `user`'s account to the person these claims name, from their profile.
  `{:error, :taken}` when that person is linked to another account, `:already_linked` when
  this account is linked to someone else at the provider.
  """
  @spec link(User.t(), map()) :: {:ok, UserIdentity.t()} | {:error, :taken | :already_linked}
  def link(%User{id: user_id} = user, claims) do
    case {find_user(claims), identity(user)} do
      {%User{id: ^user_id}, identity} -> {:ok, identity}
      {%User{}, _} -> {:error, :taken}
      {nil, %UserIdentity{}} -> {:error, :already_linked}
      {nil, nil} -> insert_identity(user, claims) |> shared(user, claims)
    end
  end

  # A link offers the provider this account's username and picture (it keeps what it lacks).
  defp shared({:ok, _identity} = linked, user, %{"sub" => subject}) do
    Profile.share(user, subject)
    linked
  end

  defp shared(other, _user, _claims), do: other

  @doc "The account's link to the provider, or nil."
  @spec identity(User.t()) :: UserIdentity.t() | nil
  def identity(%User{id: user_id}) do
    Repo.one(from i in UserIdentity, where: i.user_id == ^user_id, limit: 1)
  end
end

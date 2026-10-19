# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts do
  @moduledoc """
  Accounts: sign-up with email verification (AC-01) and sessions.
  """

  import Ecto.Query, warn: false
  alias Idejo.Federation
  alias Idejo.Repo

  alias Idejo.Accounts.{Invite, User, UserNotifier, UserToken}
  alias Idejo.Audit
  alias Idejo.Settings

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

  @doc """
  Gets a single user, or `nil`.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Lists users for the admin panel (AD-02), newest first, one page at a time.

  Returns `{users, more?}`, where `more?` tells whether a next page exists.

  ## Options

    * `:page` - the page number, from 1. Defaults to 1.
    * `:per_page` - users per page. Defaults to 50.
  """
  @spec list_users(keyword()) :: {[User.t()], boolean()}
  def list_users(opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 50)
    page = max(Keyword.get(opts, :page, 1), 1)

    users =
      Repo.all(
        from u in User,
          order_by: [desc: u.created_at, desc: u.id],
          offset: ^((page - 1) * per_page),
          limit: ^(per_page + 1)
      )

    {Enum.take(users, per_page), length(users) > per_page}
  end

  ## Sign-up

  @doc """
  Signs up a user with email, username, display name and password.

  The account is created with a stable URI (FD-01) and a `create` activity (FD-02) in one
  transaction. The email address is not verified yet; see
  `deliver_user_confirmation_instructions/2`.

  While registration is invite-only (AC-02), `attrs` must carry a valid `invite_code`; the
  invite is used up in the same transaction.

  ## Options

    * `:confirmed` - creates the account with its email already verified.
    * `:skip_invite` - signs up without an invite even when registration is invite-only.

  Only the first-run wizard uses these options, for the owner (AD-01).
  """
  @spec register_user(map(), keyword()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs, opts \\ []) do
    id = Federation.generate_id()
    uri = Federation.uri(:user, id)

    changeset =
      %User{id: id, uri: uri}
      |> User.registration_changeset(attrs)
      |> then(&if(opts[:confirmed], do: User.confirm_changeset(&1), else: &1))

    Repo.transact(fn ->
      {invite, changeset} = check_invite(changeset, opts)

      with {:ok, user} <- Repo.insert(changeset),
           :ok <- use_invite(invite, user),
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

  # Locks the invite so two sign-ups cannot use it at once. An invalid invite is added to the
  # changeset's errors, so the form shows it together with any other error.
  defp check_invite(changeset, opts) do
    if opts[:skip_invite] || Settings.get(:registration_mode) != "invite_only" do
      {nil, changeset}
    else
      code = Ecto.Changeset.get_field(changeset, :invite_code)

      case code && Repo.one(usable_invite_query(code)) do
        %Invite{} = invite ->
          {invite, changeset}

        nil ->
          {nil,
           Ecto.Changeset.add_error(changeset, :invite_code, "is not valid, used or expired")}
      end
    end
  end

  defp usable_invite_query(code) do
    from i in Invite,
      where: i.code == ^code and is_nil(i.used_by) and i.expires_at > ^DateTime.utc_now(),
      lock: "FOR UPDATE"
  end

  defp use_invite(nil, _user), do: :ok

  defp use_invite(%Invite{} = invite, %User{id: user_id}) do
    invite
    |> Ecto.Changeset.change(used_by: user_id, used_at: DateTime.utc_now(:second))
    |> Repo.update()
    |> case do
      {:ok, _invite} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  ## Invites (AC-02)

  @doc """
  Creates a single-use invite valid for 7 days, as `admin`, with an `invite.create` audit
  entry. The invite link is built by the web layer from `invite.code`.
  """
  @spec create_invite(User.t()) :: {:ok, Invite.t()}
  def create_invite(%User{} = admin) do
    now = DateTime.utc_now(:second)

    invite = %Invite{
      code: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
      created_by: admin.id,
      expires_at: DateTime.add(now, Invite.validity_in_days(), :day)
    }

    Repo.transact(fn ->
      with {:ok, invite} <- Repo.insert(invite),
           # The audit log keeps only the start of the code: the code itself lets one in.
           {:ok, _} <-
             Audit.record(admin, "invite.create", nil, %{
               "code_start" => String.slice(invite.code, 0, 4),
               "expires_at" => DateTime.to_iso8601(invite.expires_at)
             }) do
        {:ok, invite}
      end
    end)
  end

  @doc """
  Lists invites, newest first, with who created and who used them.
  """
  @spec list_invites(keyword()) :: [Invite.t()]
  def list_invites(opts \\ []) do
    Repo.all(
      from i in Invite,
        order_by: [desc: i.created_at, desc: i.code],
        limit: ^Keyword.get(opts, :limit, 100),
        preload: [:creator, :user]
    )
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
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
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

  ## Password reset (AC-02)

  @doc """
  Emails a password reset link, valid for one day, to the user.

  `reset_url_fun` receives the encoded token and returns the link.
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_url_fun)
      when is_function(reset_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_url_fun.(encoded_token))
  end

  @doc """
  Gets the user with an email address, or `nil`.
  """
  def get_user_by_email(email) when is_binary(email), do: Repo.get_by(User, email: email)

  @doc """
  Gets the user a valid password reset token was sent to, or `nil`.
  """
  @spec get_user_by_reset_password_token(String.t()) :: User.t() | nil
  def get_user_by_reset_password_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Returns a changeset for the new-password form.
  """
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Sets a new password and ends every session of the user (SP-02): all their tokens, sessions
  and emailed links alike, are deleted in the same transaction.

  Returns the socket ids of the ended sessions, so the web layer can disconnect their
  LiveViews.
  """
  @spec reset_user_password(User.t(), map()) ::
          {:ok, {User.t(), [String.t()]}} | {:error, Ecto.Changeset.t()}
  def reset_user_password(%User{} = user, attrs) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(User.password_changeset(user, attrs)) do
        tokens = from(t in UserToken, where: t.user_id == ^user.id)

        socket_ids = session_socket_ids(user)
        Repo.delete_all(tokens)
        {:ok, {user, socket_ids}}
      end
    end)
  end

  @doc """
  Returns the socket ids of the user's signed-in browser sessions, so the web layer can
  disconnect their LiveViews, e.g. when their roles change (RP-06).
  """
  @spec session_socket_ids(User.t()) :: [String.t()]
  def session_socket_ids(%User{id: user_id}) do
    Repo.all(
      from t in UserToken,
        where: t.user_id == ^user_id and t.context == "session" and not is_nil(t.socket_id),
        distinct: true,
        select: t.socket_id
    )
  end

  ## Profile (AC-04)

  @doc """
  Returns a changeset for the profile form.
  """
  def change_user_profile(%User{} = user, attrs \\ %{}), do: User.profile_changeset(user, attrs)

  @doc """
  Updates the user's own profile: the display name. Records an `update` activity (FD-02)
  when it changes.
  """
  @spec update_user_profile(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_profile(%User{} = user, attrs) do
    case User.profile_changeset(user, attrs) do
      %Ecto.Changeset{valid?: true, changes: changes} when changes == %{} -> {:ok, user}
      changeset -> Repo.transact(fn -> save_profile(changeset) end)
    end
  end

  defp save_profile(changeset) do
    with {:ok, user} <- Repo.update(changeset),
         {:ok, _activity} <-
           Repo.insert(
             Federation.activity_changeset(%{
               actor_uri: user.uri,
               verb: "update",
               object_uri: user.uri,
               payload: %{
                 "type" => "Person",
                 "username" => user.username,
                 "name" => user.display_name
               }
             })
           ) do
      {:ok, user}
    end
  end

  ## Session

  @doc """
  Makes a new id for a browser session. LiveViews opened in the session join a topic built
  from it, so they can be disconnected together.
  """
  @spec new_session_socket_id() :: String.t()
  def new_session_socket_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  @doc """
  Generates a session token for the browser session `socket_id`. A reissued token keeps the
  socket id of the session it replaces.
  """
  def generate_user_session_token(user, socket_id \\ new_session_socket_id()) do
    {token, user_token} = UserToken.build_session_token(user, socket_id)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Returns the browser session's socket id stored with a session token, or `nil`.
  """
  @spec session_socket_id(binary()) :: String.t() | nil
  def session_socket_id(token) do
    Repo.one(
      from t in UserToken,
        where: t.token == ^token and t.context == "session",
        select: t.socket_id
    )
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

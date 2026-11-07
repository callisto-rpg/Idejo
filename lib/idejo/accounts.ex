# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts do
  @moduledoc """
  Accounts: sign-up with email verification (AC-01) and sessions.
  """

  import Ecto.Query, warn: false
  alias Idejo.Access
  alias Idejo.Access.UserRole
  alias Idejo.Federation
  alias Idejo.Messages.Body
  alias Idejo.Moderation
  alias Idejo.Notifications.{Digest, EmailPreference}
  alias Idejo.Push
  alias Idejo.Repo
  alias Idejo.Uploads

  alias Idejo.Accounts.{Invite, OIDC, User, UserIdentity, UserIgnore, UserNotifier, UserToken}
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
    * `:skip_invite` - creates the account whatever the registration mode: no invite needed
      when invite-only, and allowed when closed.
    * `:welcomed` - shows no welcome card (the owner, who wrote what it says).

  Only setup, the wizard or `bin/idejo-admin setup` (AD-01, AD-14), uses these options, for
  the owner.
  """
  @spec register_user(map(), keyword()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs, opts \\ []) do
    id = Federation.generate_id()
    uri = Federation.uri(:user, id)

    changeset =
      %User{id: id, uri: uri}
      |> User.registration_changeset(attrs)
      |> then(&if(opts[:confirmed], do: User.confirm_changeset(&1), else: &1))
      |> then(&if(opts[:welcomed], do: mark_welcomed_changeset(&1), else: &1))

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

  defp mark_welcomed_changeset(changeset),
    do: Ecto.Changeset.put_change(changeset, :welcomed_at, DateTime.utc_now(:second))

  @doc """
  A username made from `candidate` that nobody has yet: other characters than letters,
  digits and `_` become `_`, at most 30; `fallback` when shorter than 3;
  a number added when taken. For accounts made without a sign-up form (AD-14, AC-09).
  """
  @spec free_username(String.t() | nil, String.t()) :: String.t()
  def free_username(candidate, fallback \\ "member") do
    base = (candidate || "") |> String.replace(~r/[^A-Za-z0-9_]/, "_") |> String.slice(0, 30)
    base = if String.length(base) < 3, do: fallback, else: base

    if username_taken?(base), do: suffixed(String.slice(base, 0, 25), 10), else: base
  end

  defp suffixed(base, 0), do: base <> "_" <> Integer.to_string(System.unique_integer([:positive]))

  defp suffixed(base, tries) do
    candidate = base <> "_" <> Integer.to_string(:rand.uniform(9999))
    if username_taken?(candidate), do: suffixed(base, tries - 1), else: candidate
  end

  defp username_taken?(username) do
    Repo.exists?(
      from u in User, where: fragment("lower(?)", u.username) == ^String.downcase(username)
    )
  end

  @doc """
  Whether people may sign up at all: false while registration is closed (steward decision,
  2026-11-02). Sign-up links are hidden then.
  """
  @spec sign_ups_open?() :: boolean()
  def sign_ups_open?, do: Settings.get(:registration_mode) != "closed"

  @doc """
  Records that the user has seen the welcome card (steward decision, 2026-10-23): it shows on
  a new member's first visit until then.
  """
  @spec mark_welcomed(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def mark_welcomed(%User{welcomed_at: nil} = user),
    do: user |> Ecto.Changeset.change() |> mark_welcomed_changeset() |> Repo.update()

  def mark_welcomed(%User{} = user), do: {:ok, user}

  # Locks the invite so two sign-ups cannot use it at once. An invalid invite is added to the
  # changeset's errors, so the form shows it together with any other error. Closed: nobody
  # signs up, invite or not.
  defp check_invite(changeset, opts) do
    mode = if opts[:skip_invite], do: "open", else: Settings.get(:registration_mode)

    case mode do
      "closed" ->
        {nil, Ecto.Changeset.add_error(changeset, :email, "cannot sign up: sign-ups are closed")}

      "invite_only" ->
        find_invite(changeset)

      _open ->
        {nil, changeset}
    end
  end

  defp find_invite(changeset) do
    code = Ecto.Changeset.get_field(changeset, :invite_code)

    case code && Repo.one(usable_invite_query(code)) do
      %Invite{} = invite ->
        {invite, changeset}

      nil ->
        {nil, Ecto.Changeset.add_error(changeset, :invite_code, "is not valid, used or expired")}
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
  Gets the user a valid password reset token was sent to, or `nil`. The link an owner made
  by `bin/idejo-admin setup` gets to choose a first password (AD-14) is one too.
  """
  @spec get_user_by_reset_password_token(String.t()) :: User.t() | nil
  def get_user_by_reset_password_token(token) when is_binary(token) do
    Enum.find_value(["reset_password", "set_password"], fn context ->
      with {:ok, query} <- UserToken.verify_email_token_query(token, context),
           {user, _token} <- Repo.one(query) do
        user
      else
        _ -> nil
      end
    end)
  end

  @doc """
  Makes the link token with which an owner made by `bin/idejo-admin setup` (AD-14) chooses
  their first password on the password reset page, for
  #{UserToken.set_password_validity_in_days()} days. Setting it deletes it, like every token
  of the account.
  """
  @spec create_set_password_token(User.t()) :: String.t()
  def create_set_password_token(%User{} = user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "set_password")
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Returns a changeset for the new-password form.
  """
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Changes the password from the profile (AC-01), given the current one in
  `attrs["current_password"]`. Every other session of the user ends (SP-02): their tokens,
  and any emailed links, are deleted in the same transaction; the session holding
  `kept_token` stays signed in.

  Returns the socket ids of the ended sessions, so the web layer can disconnect their
  LiveViews.
  """
  @spec update_user_password(User.t(), map(), binary()) ::
          {:ok, {User.t(), [String.t()]}} | {:error, Ecto.Changeset.t()}
  def update_user_password(%User{} = user, attrs, kept_token) when is_binary(kept_token) do
    changeset =
      user
      |> Ecto.Changeset.change()
      # First, so a wrong current password costs no hashing of the new one.
      |> User.validate_current_password(attrs["current_password"])
      |> User.password_changeset(attrs)

    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        kept_socket_id = session_socket_id(kept_token)
        others = from(t in UserToken, where: t.user_id == ^user.id and t.token != ^kept_token)
        socket_ids = Enum.reject(session_socket_ids(user), &(&1 == kept_socket_id))
        Repo.delete_all(others)
        :ok = Push.delete_for_sessions(socket_ids)
        {:ok, {user, socket_ids}}
      end
    end)
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
        :ok = Push.delete_for_user(user)
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

  @doc "Returns a changeset for the user's writing preferences."
  @spec change_user_writing(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_writing(%User{} = user, attrs \\ %{}), do: User.writing_changeset(user, attrs)

  @doc """
  Updates the user's writing preferences: "Automatic punctuation" (steward decision,
  2026-10-26), which `Idejo.Messages.commit/4` and the composer read from the author, and
  "Use the graphical composer" (TP-11; steward decision, 2026-11-02), which `IdejoWeb.TopicLive`
  reads at mount. A private preference: no activity.
  """
  @spec update_user_writing(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_writing(%User{} = user, attrs),
    do: user |> User.writing_changeset(attrs) |> Repo.update()

  @doc "Returns a changeset for the message controls preferences."
  @spec change_user_controls(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_controls(%User{} = user, attrs \\ %{}),
    do: User.controls_changeset(user, attrs)

  @doc """
  Updates where a message's actions always show: "Show message controls on mobile" and "on
  desktop" (steward decision, 2026-10-31), which `IdejoWeb.TopicLive` reads at mount. A
  private preference: no activity.
  """
  @spec update_user_controls(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_controls(%User{} = user, attrs),
    do: user |> User.controls_changeset(attrs) |> Repo.update()

  @doc "Returns a changeset for the bio (AC-04)."
  @spec change_user_bio(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_bio(%User{} = user, attrs \\ %{}), do: User.bio_changeset(user, attrs)

  @doc """
  Sets the user's bio (AC-04): Markdown, stored with its HTML rendered as the user writes it
  (FD-03; inline links resolve as they may view them). Records an `update` activity (FD-02)
  carrying it as `summary` when it changes.
  """
  @spec update_user_bio(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_bio(%User{} = user, attrs) do
    case User.bio_changeset(user, attrs) do
      %Ecto.Changeset{valid?: true, changes: changes} when changes == %{} ->
        {:ok, user}

      %Ecto.Changeset{valid?: true} = changeset ->
        Repo.transact(fn -> save_bio(user, changeset) end)

      changeset ->
        {:error, Map.put(changeset, :action, :update)}
    end
  end

  defp save_bio(user, changeset) do
    bio = Ecto.Changeset.get_change(changeset, :bio_md)
    html = if bio, do: Body.to_html(bio, author: user)

    with {:ok, user} <- changeset |> Ecto.Changeset.put_change(:bio_html, html) |> Repo.update(),
         {:ok, _activity} <- Repo.insert(bio_activity(user)) do
      {:ok, user}
    end
  end

  defp bio_activity(user) do
    Federation.activity_changeset(%{
      actor_uri: user.uri,
      verb: "update",
      object_uri: user.uri,
      payload: %{"type" => "Person", "username" => user.username, "summary" => user.bio_html}
    })
  end

  @doc "Returns a changeset for receiving private messages."
  @spec change_user_private_messages(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_private_messages(%User{} = user, attrs \\ %{}),
    do: User.private_messages_changeset(user, attrs)

  @doc """
  Turns receiving private messages on or off (steward decision, 2026-10-27): off, nobody
  starts a conversation with the user or writes in one they are in. A private preference:
  no activity.
  """
  @spec update_user_private_messages(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_private_messages(%User{} = user, attrs),
    do: user |> User.private_messages_changeset(attrs) |> Repo.update()

  @doc """
  Updates the user's own profile: the display name and the user tag (steward decision,
  2026-10-27). Records an `update` activity (FD-02) when either changes.
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

  ## Avatar (AC-04)

  @doc """
  Sets the user's avatar from the image at `path` (`Idejo.Uploads.store_avatar/2`), records
  an `update` activity and deletes the picture it replaces. `:dark` sets the picture shown
  with the dark theme instead (steward decision, 2026-10-23).
  """
  @spec set_avatar(User.t(), Path.t(), :light | :dark) ::
          {:ok, User.t()}
          | {:error, :too_large | :not_an_image | :too_many_pixels | :not_saved | :rate_limited}
  def set_avatar(%User{} = user, path, theme \\ :light) when theme in [:light, :dark] do
    with {:ok, upload} <- Uploads.store_avatar(user, path) do
      Repo.transact(fn -> replace_avatar(user, avatar_field(theme), upload.id) end)
    end
  end

  @doc """
  Removes the user's avatar; they are shown with their initial again (AC-04). `:dark`
  removes the dark theme's picture: the avatar shows with both themes again.
  """
  @spec remove_avatar(User.t(), :light | :dark) :: {:ok, User.t()}
  def remove_avatar(%User{} = user, theme \\ :light) when theme in [:light, :dark] do
    field = avatar_field(theme)

    if Map.fetch!(user, field),
      do: Repo.transact(fn -> replace_avatar(user, field, nil) end),
      else: {:ok, user}
  end

  defp avatar_field(:light), do: :avatar_id
  defp avatar_field(:dark), do: :avatar_dark_id

  defp replace_avatar(user, field, upload_id) do
    with {:ok, updated} <- user |> Ecto.Changeset.change([{field, upload_id}]) |> Repo.update(),
         {:ok, _activity} <- Repo.insert(Federation.activity_changeset(person_update(updated))),
         :ok <- Uploads.delete(Map.fetch!(user, field)) do
      {:ok, updated}
    end
  end

  defp person_update(user) do
    icon = Uploads.avatar_url(user)

    %{
      actor_uri: user.uri,
      verb: "update",
      object_uri: user.uri,
      payload:
        %{"type" => "Person", "username" => user.username, "name" => user.display_name}
        |> then(&if(icon, do: Map.put(&1, "icon", icon), else: &1))
    }
  end

  ## Ignoring a user (AC-06)

  @doc """
  `user` ignores `other` (AC-06): `other`'s messages are collapsed for them. Private: nothing
  is logged and `other` is never told. Refused for oneself, a deleted account and a server
  account (`{:error, :forbidden}`). Ignoring twice is fine.
  """
  @spec ignore_user(User.t(), User.t()) :: :ok | {:error, :forbidden}
  def ignore_user(%User{} = user, %User{} = other) do
    if may_ignore?(user, other) do
      now = DateTime.utc_now(:second)

      Repo.insert_all(UserIgnore, [%{user_id: user.id, ignored_id: other.id, inserted_at: now}],
        on_conflict: :nothing
      )

      :ok
    else
      {:error, :forbidden}
    end
  end

  @doc "`user` no longer ignores `other` (AC-06). Fine when they did not."
  @spec unignore_user(User.t(), User.t()) :: :ok
  def unignore_user(%User{} = user, %User{} = other) do
    Repo.delete_all(
      from i in UserIgnore, where: i.user_id == ^user.id and i.ignored_id == ^other.id
    )

    :ok
  end

  @doc "Whether `user` may ignore `other`: someone else, with an active account."
  @spec may_ignore?(User.t() | nil, User.t()) :: boolean()
  def may_ignore?(nil, _other), do: false
  def may_ignore?(%User{id: id}, %User{id: id}), do: false
  def may_ignore?(%User{}, %User{status: status}), do: status == "active"

  @doc "Whether `user` ignores `other` (AC-06); nobody signed in ignores no one."
  @spec ignoring?(User.t() | nil, User.t()) :: boolean()
  def ignoring?(nil, _other), do: false

  def ignoring?(%User{} = user, %User{} = other),
    do:
      Repo.exists?(
        from i in UserIgnore, where: i.user_id == ^user.id and i.ignored_id == ^other.id
      )

  @doc "The ids of the users `user` ignores (AC-06), in one query; none for a visitor."
  @spec ignored_ids(User.t() | nil) :: MapSet.t(Ecto.UUID.t())
  def ignored_ids(nil), do: MapSet.new()

  def ignored_ids(%User{} = user) do
    from(i in UserIgnore, where: i.user_id == ^user.id, select: i.ignored_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "The users `user` ignores (AC-06), by display name, for Profile and account."
  @spec list_ignored(User.t()) :: [User.t()]
  def list_ignored(%User{} = user) do
    Repo.all(
      from u in User,
        join: i in UserIgnore,
        on: i.ignored_id == u.id,
        where: i.user_id == ^user.id,
        order_by: [asc: fragment("lower(?)", u.display_name)]
    )
  end

  ## Bans (MO-02)

  @doc """
  Returns true while the user is banned: banned for good, or until a time still to come.
  """
  @spec banned?(User.t(), DateTime.t()) :: boolean()
  def banned?(%User{} = user, now \\ DateTime.utc_now()) do
    case user do
      %{banned_at: nil} -> false
      %{banned_until: nil} -> true
      %{banned_until: until} -> DateTime.after?(until, now)
    end
  end

  @doc """
  Records that the user is here (steward decision, 2026-10-23), for the email summary of what
  they missed: `last_seen_at` moves to now, at most every five minutes, so a page load
  rarely writes. Called for each signed-in request by `IdejoWeb.UserAuth`.
  """
  @spec seen(User.t()) :: User.t()
  def seen(%User{last_seen_at: last} = user) do
    now = DateTime.utc_now()

    if last && DateTime.diff(now, last) < 300 do
      user
    else
      Repo.update_all(from(u in User, where: u.id == ^user.id), set: [last_seen_at: now])
      %{user | last_seen_at: now}
    end
  end

  @doc """
  Bans an account, as a server moderator (`Access.server_moderator?/1`), for good (`until`
  nil) or until a time to come, with an optional reason (MO-02, steward decision). The
  account can no longer sign in; its sessions are deleted, and their socket ids returned for
  `IdejoWeb.UserAuth.disconnect_sessions/1`. Its messages stay. Logged (MO-03).

  Owners and administrators are never banned, nor is the moderator themself
  (`{:error, :not_bannable}`).
  """
  @spec ban_user(User.t(), User.t(), DateTime.t() | nil, String.t() | nil) ::
          {:ok, {User.t(), [String.t()]}}
          | {:error, :forbidden | :not_bannable | :past | Ecto.Changeset.t()}
  def ban_user(%User{} = moderator, %User{} = user, until, reason \\ nil) do
    cond do
      not Access.server_moderator?(moderator) -> {:error, :forbidden}
      user.id == moderator.id or Access.administrator?(user) -> {:error, :not_bannable}
      user.status != "active" -> {:error, :not_bannable}
      until != nil and not DateTime.after?(until, DateTime.utc_now()) -> {:error, :past}
      true -> Repo.transact(fn -> save_ban(moderator, user, until, reason) end)
    end
  end

  defp save_ban(moderator, user, until, reason) do
    socket_ids = session_socket_ids(user)

    with {:ok, banned} <-
           user
           |> Ecto.Changeset.change(banned_at: DateTime.utc_now(), banned_until: until)
           |> Repo.update(),
         {_, _} <-
           Repo.delete_all(
             from t in UserToken, where: t.user_id == ^user.id and t.context == "session"
           ),
         :ok <- Push.delete_for_user(user),
         {:ok, _} <-
           Moderation.record(moderator, "user.ban", banned,
             reason: reason,
             details: %{"until" => until && DateTime.to_iso8601(until)}
           ) do
      {:ok, {banned, socket_ids}}
    end
  end

  @doc "Lifts a ban, as a server moderator, with an optional reason; logged (MO-03)."
  @spec unban_user(User.t(), User.t(), String.t() | nil) ::
          {:ok, User.t()} | {:error, :forbidden | :not_banned | Ecto.Changeset.t()}
  def unban_user(%User{} = moderator, %User{} = user, reason \\ nil) do
    cond do
      not Access.server_moderator?(moderator) -> {:error, :forbidden}
      user.banned_at == nil -> {:error, :not_banned}
      true -> Repo.transact(fn -> save_unban(moderator, user, reason) end)
    end
  end

  defp save_unban(moderator, user, reason) do
    with {:ok, user} <-
           user |> Ecto.Changeset.change(banned_at: nil, banned_until: nil) |> Repo.update(),
         {:ok, _} <- Moderation.record(moderator, "user.unban", user, reason: reason) do
      {:ok, user}
    end
  end

  ## Account deletion (AC-07)

  @doc """
  Deletes the user's own account, given their password, or `{:oidc, at}`: the time (Unix
  seconds) they signed in again through the OpenID Connect provider their account is linked
  to, within the last five minutes (AC-09; steward decision, 2026-11-02), for members whose
  only way in is the provider.

  The row stays so the stable `uri` (FD-01) and the records that name the user keep
  working, but everything personal goes: email, username, display name and password are
  replaced, roles, sessions, emailed links and OpenID Connect links are deleted, and `status` becomes
  `"deleted"`. A `delete` activity (FD-02) is recorded in the same transaction.

  The server's last owner cannot delete their account (`{:error, :last_owner}`). Returns the
  socket ids of the ended sessions, so the web layer can disconnect their LiveViews.
  """
  @spec delete_user(User.t(), String.t() | {:oidc, integer() | nil} | nil) ::
          {:ok, {User.t(), [String.t()]}}
          | {:error, :invalid_password | :reauthentication | :last_owner}
  def delete_user(%User{} = user, {:oidc, at}) do
    if OIDC.fresh_reauth?(at) and OIDC.identity(user),
      do: Repo.transact(fn -> anonymise(user) end),
      else: {:error, :reauthentication}
  end

  def delete_user(%User{} = user, password) do
    if User.valid_password?(user, password || "") do
      Repo.transact(fn -> anonymise(user) end)
    else
      {:error, :invalid_password}
    end
  end

  @doc """
  AC-09, for a shared identity provider (Idejo Hub's ID-05, ID-06): the account linked to
  the configured provider's `subject`, deleted as AC-07 deletes one (anonymised: its messages
  stay, shown as "Deleted user"; the last owner is refused). No password or sign-in is asked:
  only the server's command line calls it, for the provider's operator. Audited as
  `user.delete_by_identity` with no admin. Returns the ended sessions' socket ids.
  """
  @spec delete_user_by_identity(String.t()) ::
          {:ok, {User.t(), [String.t()]}} | {:error, :not_found | :last_owner | :no_provider}
  def delete_user_by_identity(subject) do
    with {:ok, user} <- user_by_identity(subject) do
      Repo.transact(fn -> anonymise_audited(user) end)
    end
  end

  defp anonymise_audited(user) do
    with {:ok, result} <- anonymise(user) do
      {:ok, _} = Audit.record(nil, "user.delete_by_identity", %{"uri" => user.uri}, nil)
      {:ok, result}
    end
  end

  @doc """
  AC-09, for a shared identity provider (Idejo Hub's ID-05): the person leaves this forum but
  keeps their account. Their sessions end, their browsers stop getting pushes and their email
  summaries are turned off; their account, messages, roles and link to the provider stay, so
  signing in again with the same identity brings everything back. Audited as `user.leave`.
  Returns the ended sessions' socket ids.
  """
  @spec leave_by_identity(String.t()) ::
          {:ok, {User.t(), [String.t()]}} | {:error, :not_found | :no_provider}
  def leave_by_identity(subject) do
    with {:ok, user} <- user_by_identity(subject) do
      Repo.transact(fn ->
        socket_ids = session_socket_ids(user)
        Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id)
        :ok = Push.delete_for_user(user)

        {:ok, _} =
          Digest.update_preferences(user, Map.new(EmailPreference.options(), &{&1, false}))

        {:ok, _} = Audit.record(nil, "user.leave", %{"uri" => user.uri}, nil)
        {:ok, {user, socket_ids}}
      end)
    end
  end

  defp user_by_identity(subject) do
    with issuer when is_binary(issuer) <-
           (OIDC.config() || [])[:issuer] || {:error, :no_provider},
         %User{status: status} = user when status != "deleted" <-
           OIDC.find_user(%{"iss" => issuer, "sub" => subject}) || {:error, :not_found} do
      {:ok, user}
    else
      {:error, reason} -> {:error, reason}
      %User{} -> {:error, :not_found}
    end
  end

  defp anonymise(user) do
    with :ok <- Access.ensure_not_last_owner(user) do
      socket_ids = session_socket_ids(user)
      Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id)
      Repo.delete_all(from ur in UserRole, where: ur.user_id == ^user.id)
      # AC-09: the provider's person is no longer this account.
      Repo.delete_all(from i in UserIdentity, where: i.user_id == ^user.id)
      # MO-04: their topics still waiting for approval.
      Repo.delete_all(from p in Idejo.Forum.PendingTopic, where: p.author_id == ^user.id)
      # AC-06: whom they ignored, and who ignored them.
      Repo.delete_all(
        from i in UserIgnore, where: i.user_id == ^user.id or i.ignored_id == ^user.id
      )

      :ok = Push.delete_for_user(user)

      # Neither placeholder can be signed up with: usernames have no hyphen, emails need an @.
      deleted =
        user
        |> Ecto.Changeset.change(
          email: "deleted:" <> user.id,
          username: "deleted-" <> user.id,
          display_name: "Deleted user",
          user_tag: nil,
          bio_md: nil,
          bio_html: nil,
          password_hash: Argon2.hash_pwd_salt(:crypto.strong_rand_bytes(32)),
          confirmed_at: nil,
          status: "deleted",
          avatar_id: nil,
          avatar_dark_id: nil
        )
        |> Repo.update!()

      # AC-04: the pictures go with the account.
      :ok = Uploads.delete(user.avatar_id)
      :ok = Uploads.delete(user.avatar_dark_id)

      Repo.insert!(
        Federation.activity_changeset(%{
          actor_uri: user.uri,
          verb: "delete",
          object_uri: user.uri,
          payload: %{"type" => "Person"}
        })
      )

      {:ok, {deleted, socket_ids}}
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

    # MO-02: a banned account has no session, even one left over.
    case Repo.one(query) do
      {user, _inserted_at} = found -> if banned?(user), do: nil, else: found
      nil -> nil
    end
  end

  @doc """
  Deletes the signed token with the given context (sign-out), and the browser push
  subscriptions made in its session (PN-13).
  """
  def delete_user_session_token(token) do
    socket_id = session_socket_id(token)
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok = Push.delete_for_sessions(List.wrap(socket_id))
  end
end

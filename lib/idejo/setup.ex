# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Setup do
  @moduledoc """
  First-run setup (AD-01): until the server has an owner, every page leads to the setup
  wizard, which asks for the server name, the owner account and the email settings.

  Anyone could reach a fresh server first, so the wizard requires a setup code. It is made
  when the node starts and written to the app log; restarting makes a new one. Once an owner exists the wizard is gone for good: owners cannot be removed (see the
  lockout rule in CLAUDE.md).

  `complete_headless/1` is the same setup from the command line (`bin/idejo-admin setup`,
  AD-14), through the same steps (`set_up/4`): the owner is made as an invite, with no
  password anyone knows, and chooses one from a link (`Accounts.create_set_password_token/1`)
  that is emailed, or handed back for the operator when email cannot go out. Its audit
  entries have no admin, as the command line's do.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Idejo.Access
  alias Idejo.Access.{Role, UserRole}
  alias Idejo.Accounts
  alias Idejo.Accounts.{User, UserNotifier}
  alias Idejo.Audit
  alias Idejo.Repo
  alias Idejo.Settings

  # The email settings the wizard asks for; anything else in the form is ignored.
  @settings_keys ~w(server_name mail_from smtp_host smtp_port smtp_security smtp_username
                    smtp_password)

  # Two concurrent submissions must not both create an owner.
  @lock_key 0x1DE10_0001

  @doc """
  Returns true while the server has no owner, so the wizard is needed.
  """
  @spec needed?() :: boolean()
  def needed? do
    not Repo.exists?(
      from ur in UserRole,
        join: r in Role,
        on: r.id == ur.role_id,
        where: r.built_in and r.name == "owner"
    )
  end

  @doc """
  The setup code of this node, made on first use. It lives only in memory.
  """
  @spec token() :: String.t()
  def token do
    case :persistent_term.get({__MODULE__, :token}, nil) do
      nil ->
        token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
        :persistent_term.put({__MODULE__, :token}, token)
        token

      token ->
        token
    end
  end

  @doc """
  Returns true when `candidate` is this node's setup code.
  """
  @spec valid_token?(term()) :: boolean()
  def valid_token?(candidate) when is_binary(candidate),
    do: Plug.Crypto.secure_compare(candidate, token())

  def valid_token?(_candidate), do: false

  @doc """
  Writes the setup link to the log while setup is needed. Runs once at boot.
  """
  @spec announce() :: :ok
  def announce do
    if needed?() do
      Logger.warning("""
      Idejo is not set up yet. Open this link to run the setup wizard:

          #{Application.fetch_env!(:idejo, :base_uri)}/setup?code=#{token()}

      The code changes each time the server restarts.
      """)
    end

    :ok
  end

  @doc """
  Returns the changesets for an empty or re-shown wizard form.
  """
  @spec change(map(), map()) :: %{owner: Ecto.Changeset.t(), settings: Ecto.Changeset.t()}
  def change(owner_attrs \\ %{}, settings_attrs \\ %{}) do
    %{
      owner: Accounts.change_user_registration(%User{}, owner_attrs),
      settings: Settings.change_settings(Map.take(settings_attrs, @settings_keys))
    }
  end

  @doc """
  Completes setup with the setup code, the owner's account and the settings, in one
  transaction: creates the owner with a verified email, gives them the owner role, and saves
  the settings as the owner. Both role and settings are audited (SP-06).

  Returns `{:error, :invalid_code}`, `{:error, :already_set_up}`, or
  `{:error, %{owner: changeset, settings: changeset}}` when a field is wrong.
  """
  @spec complete(term(), map(), map()) ::
          {:ok, User.t()}
          | {:error, :invalid_code | :already_set_up}
          | {:error, %{owner: Ecto.Changeset.t(), settings: Ecto.Changeset.t()}}
  def complete(code, owner_attrs, settings_attrs) do
    settings_attrs = Map.take(settings_attrs, @settings_keys)
    settings = Settings.change_settings(settings_attrs) |> Map.put(:action, :insert)

    cond do
      not valid_token?(code) ->
        {:error, :invalid_code}

      not settings.valid? ->
        {:error, %{owner: owner_form(owner_attrs), settings: settings}}

      true ->
        owner_attrs
        |> create_owner_in_transaction(settings_attrs)
        |> with_forms(settings)
    end
  end

  # A failed insert aborts the transaction, so the settings form is built before it.
  defp create_owner_in_transaction(owner_attrs, settings_attrs),
    do: Repo.transact(fn -> create_owner(owner_attrs, settings_attrs) end)

  defp with_forms({:error, {:owner, owner}}, settings),
    do: {:error, %{owner: owner, settings: settings}}

  defp with_forms(result, _settings), do: result

  defp create_owner(owner_attrs, settings_attrs),
    do: set_up(owner_attrs, settings_attrs, :owner)

  # The steps of every setup, inside its transaction: an owner, verified and welcomed, the
  # owner role, the settings. The wizard's audit entries name the owner who filled it in;
  # the command line's name nobody (`audit_as: :nobody`), like its other commands.
  defp set_up(owner_attrs, settings_attrs, audit_as) do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_key])

    with :ok <- ensure_needed(),
         {:ok, owner} <- register_owner(owner_attrs) do
      actor = if audit_as == :owner, do: owner

      with :ok <- Access.grant_role(owner, Access.built_in_role!(:owner)),
           {:ok, _} <-
             Audit.record(actor, "user_role.grant", nil, %{
               "user" => owner.uri,
               "role" => "owner"
             }),
           {:ok, _} <- Settings.update_settings(actor, settings_attrs) do
        {:ok, owner}
      end
    end
  end

  @doc """
  Sets the server up from the command line (AD-14): `name` (the server name), `owner_email`
  and, optionally, `registration_mode` (a value of `Settings.registration_modes/0`; left as
  it is, open, without it). The owner's username and display name come from the email
  address (the part before `@`); the display name can be changed later, the username not.

  Returns the owner and their link to choose a password, after trying to email it:
  `delivered` is `:ok` or the mailer's `{:error, reason}`, when the operator must hand the
  link over. `{:error, :already_set_up}` once an owner exists, changing nothing.
  """
  @spec complete_headless(map()) ::
          {:ok, %{owner: User.t(), url: String.t(), delivered: :ok | {:error, term()}}}
          | {:error, :already_set_up | Ecto.Changeset.t()}
  def complete_headless(%{name: name, owner_email: email} = attrs) do
    settings_attrs =
      Map.reject(
        %{"server_name" => name, "registration_mode" => attrs[:registration_mode]},
        fn {_key, value} -> is_nil(value) end
      )

    settings = Settings.change_settings(settings_attrs) |> Map.put(:action, :insert)

    with true <- settings.valid? || {:error, settings},
         {:ok, {owner, token}} <- headless_in_transaction(email, settings_attrs) do
      url = Application.fetch_env!(:idejo, :base_uri) <> "/users/reset-password/" <> token
      {:ok, %{owner: owner, url: url, delivered: deliver_invite(owner, url)}}
    end
  end

  defp deliver_invite(owner, url) do
    case UserNotifier.deliver_owner_invite(owner, url) do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp headless_in_transaction(email, settings_attrs) do
    Repo.transact(fn ->
      with {:ok, owner} <- set_up(headless_owner(email), settings_attrs, :nobody) do
        {:ok, {owner, Accounts.create_set_password_token(owner)}}
      end
    end)
    |> case do
      {:error, {:owner, changeset}} -> {:error, changeset}
      result -> result
    end
  end

  # No password anyone knows: a random one, never shown, replaced from the link.
  defp headless_owner(email) do
    email = String.trim(email)
    local = email |> String.split("@") |> hd() |> String.trim()

    %{
      "email" => email,
      "username" => username_from(local),
      "display_name" =>
        local |> String.slice(0, 60) |> then(&if(&1 == "", do: "Owner", else: &1)),
      "password" => Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    }
  end

  defp username_from(local) do
    base = local |> String.replace(~r/[^A-Za-z0-9_]/, "_") |> String.slice(0, 30)
    base = if String.length(base) < 3, do: "owner", else: base

    taken? =
      &Repo.exists?(
        from u in User, where: fragment("lower(?)", u.username) == ^String.downcase(&1)
      )

    if taken?.(base),
      do: String.slice(base, 0, 25) <> "_" <> Integer.to_string(:rand.uniform(9999)),
      else: base
  end

  defp ensure_needed, do: if(needed?(), do: :ok, else: {:error, :already_set_up})

  defp register_owner(owner_attrs) do
    case Accounts.register_user(owner_attrs, confirmed: true, skip_invite: true, welcomed: true) do
      {:ok, owner} -> {:ok, owner}
      {:error, changeset} -> {:error, {:owner, changeset}}
    end
  end

  defp owner_form(owner_attrs) do
    %User{} |> Accounts.change_user_registration(owner_attrs) |> Map.put(:action, :insert)
  end
end

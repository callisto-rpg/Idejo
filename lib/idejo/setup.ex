# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Setup do
  @moduledoc """
  First-run setup (AD-01): until the server has an owner, every page leads to the setup
  wizard, which asks for the server name, the owner account and the email settings.

  Anyone could reach a fresh server first, so the wizard requires a setup code. It is made
  when the node starts and written to the app log; restarting makes a new one. Once an owner exists the wizard is gone for good: owners cannot be removed (see the
  lockout rule in CLAUDE.md).
  """

  require Logger

  import Ecto.Query, warn: false

  alias Idejo.Access
  alias Idejo.Access.{Role, UserRole}
  alias Idejo.Accounts
  alias Idejo.Accounts.User
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

  defp create_owner(owner_attrs, settings_attrs) do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_key])

    with :ok <- ensure_needed(),
         {:ok, owner} <- register_owner(owner_attrs),
         :ok <- Access.grant_role(owner, Access.built_in_role!(:owner)),
         {:ok, _} <-
           Audit.record(owner, "user_role.grant", nil, %{
             "user" => owner.uri,
             "role" => "owner"
           }),
         {:ok, _} <- Settings.update_settings(owner, settings_attrs) do
      {:ok, owner}
    end
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

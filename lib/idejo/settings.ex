# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Settings do
  @moduledoc """
  Server-wide settings (AD-02), changed by administrators from the admin panel.

  Each key is declared in `@definitions` with its default; a key without a stored row uses
  the default. Every change writes an audit entry (SP-06) in the same transaction.

  Keys in v0.1 so far: `server_name`. Later requirements add theirs (registration mode in
  AC-02, SMTP in AD-08, the growing-message window in AD-04).
  """

  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Repo
  alias Idejo.Settings.Setting

  @definitions %{
    server_name: %{default: "Idejo", max_length: 80}
  }

  @type key :: :server_name

  @doc """
  Returns the value of a setting, or its default when it was never set.
  """
  @spec get(key()) :: String.t()
  def get(key) when is_map_key(@definitions, key) do
    case Repo.get(Setting, Atom.to_string(key)) do
      %Setting{value: value} -> value
      nil -> @definitions[key].default
    end
  end

  @doc """
  Returns every setting with its current value.
  """
  @spec all() :: %{key() => String.t()}
  def all do
    stored = Map.new(Repo.all(Setting), &{&1.key, &1.value})

    Map.new(@definitions, fn {key, %{default: default}} ->
      {key, Map.get(stored, Atom.to_string(key), default)}
    end)
  end

  @doc """
  Returns a changeset for the settings form, over the current values.
  """
  @spec change_settings(map()) :: Ecto.Changeset.t()
  def change_settings(attrs \\ %{}) do
    types = Map.new(@definitions, fn {key, _} -> {key, :string} end)

    {all(), types}
    |> cast(attrs, Map.keys(types))
    |> update_change(:server_name, &(&1 && String.trim(&1)))
    |> validate_required([:server_name])
    |> validate_length(:server_name, max: @definitions.server_name.max_length)
  end

  @doc """
  Saves the settings that changed, as `admin`, with one `settings.update` audit entry
  holding the old and new values of the changed keys. Nothing is written when nothing
  changed.
  """
  @spec update_settings(User.t(), map()) ::
          {:ok, %{key() => String.t()}} | {:error, Ecto.Changeset.t()}
  def update_settings(%User{} = admin, attrs) do
    changeset = change_settings(attrs)

    with {:ok, new} <- apply_action(changeset, :update) do
      save(admin, changeset.data, new, Map.keys(changeset.changes))
    end
  end

  defp save(_admin, _old, new, []), do: {:ok, new}

  defp save(admin, old, new, changed) do
    Repo.transact(fn -> save_changed(admin, old, new, changed) end)
  end

  defp save_changed(admin, old, new, changed) do
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(changed, fn key ->
        %{key: Atom.to_string(key), value: new[key], inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(Setting, rows,
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )

    with {:ok, _entry} <-
           Audit.record(
             admin,
             "settings.update",
             Audit.snapshot(old, changed),
             Audit.snapshot(new, changed)
           ) do
      {:ok, new}
    end
  end
end

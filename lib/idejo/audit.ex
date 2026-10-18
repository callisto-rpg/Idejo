# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Audit do
  @moduledoc """
  Admin audit log (SP-06). Every change an administrator makes to settings, roles, role
  assignments, categories or permissions records one entry.

  Call `record/4` inside the same transaction as the change, so a change is never saved
  without its entry. The log is append-only: the database refuses updates and deletes.

  `before` and `after` are stored as JSON. Pass only the fields that changed meaning, built
  with `snapshot/2`, and never secrets such as passwords; record that a secret changed with
  a placeholder instead.
  """

  import Ecto.Query, warn: false
  alias Idejo.Accounts.User
  alias Idejo.Audit.Entry
  alias Idejo.Repo

  @doc """
  Records a change. `admin` is the user who made it, or `nil` for the command line.

  `change` names the subject and the action, e.g. `"role.create"` or `"settings.update"`.
  `before` is `nil` for something new, `after` is `nil` for something removed.

      Repo.transact(fn ->
        with {:ok, role} <- Repo.insert(changeset),
             {:ok, _} <- Audit.record(admin, "role.create", nil, Audit.snapshot(role, [:name])) do
          {:ok, role}
        end
      end)
  """
  @spec record(User.t() | nil, String.t(), map() | nil, map() | nil) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def record(admin, change, before, after_) do
    %Entry{}
    |> Entry.changeset(%{
      admin_id: admin && admin.id,
      change: change,
      before: before,
      after: after_
    })
    |> Repo.insert()
  end

  @doc """
  Takes the given fields of a struct or map as a JSON-ready map with string keys.
  """
  @spec snapshot(struct() | map(), [atom()]) :: map()
  def snapshot(data, fields) when is_list(fields) do
    Map.new(fields, fn field -> {Atom.to_string(field), Map.get(data, field)} end)
  end

  @doc """
  Lists entries, newest first, with the admin preloaded.

  ## Options

    * `:limit` - the maximum number of entries. Defaults to 100.
  """
  @spec list_entries(keyword()) :: [Entry.t()]
  def list_entries(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Repo.all(
      from e in Entry,
        order_by: [desc: e.created_at, desc: e.id],
        limit: ^limit,
        preload: [:admin]
    )
  end
end

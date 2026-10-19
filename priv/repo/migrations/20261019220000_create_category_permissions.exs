# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateCategoryPermissions do
  use Ecto.Migration

  # RP-04, MVP §6: category_id, role_id, right, effect. A row without category_id is the
  # role's server-wide setting; a category row overrides it for that role (allow or deny).
  # No row means unset.
  def up do
    create table(:category_permissions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :category_id, references(:categories, type: :binary_id, on_delete: :delete_all)
      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all), null: false
      add :right, :string, null: false
      add :effect, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:category_permissions, [:category_id, :role_id, :right],
             nulls_distinct: false
           )

    create index(:category_permissions, [:role_id])

    create constraint(:category_permissions, :right_is_known,
             check: "\"right\" IN ('view', 'start', 'post', 'moderate')"
           )

    create constraint(:category_permissions, :effect_is_known,
             check: "effect IN ('allow', 'deny')"
           )

    flush()

    # Server-wide defaults, so a new category works out of the box; administrators change
    # them in the permission grid (RP-05). Owner and administrator need none: they always
    # have every right.
    defaults = %{
      "guest" => ~w(view),
      "member" => ~w(view start post),
      "moderator" => ~w(view start post moderate)
    }

    for {role, rights} <- defaults, right <- rights do
      execute """
      INSERT INTO category_permissions (id, role_id, "right", effect, inserted_at, updated_at)
      SELECT '#{Ecto.UUID.generate(version: 7)}', id, '#{right}', 'allow', now(), now()
      FROM roles WHERE built_in AND name = '#{role}'
      """
    end
  end

  def down do
    drop table(:category_permissions)
  end
end

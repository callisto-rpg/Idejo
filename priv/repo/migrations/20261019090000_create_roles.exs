# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  # RP-01: built-in roles, highest rank first (lower position = higher rank).
  @built_in ~w(owner administrator moderator member guest)

  def up do
    # MVP §6. `colour` is a hex string such as "#3366ff"; built-in roles start without one.
    create table(:roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :colour, :string
      add :position, :integer, null: false
      add :built_in, :boolean, null: false, default: false

      timestamps(type: :utc_datetime, inserted_at: :created_at)
    end

    create unique_index(:roles, [:name])

    create table(:user_roles, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all),
        primary_key: true
    end

    create index(:user_roles, [:role_id])

    flush()

    for {name, position} <- Enum.with_index(@built_in) do
      id = Ecto.UUID.generate(version: 7)

      execute """
      INSERT INTO roles (id, name, position, built_in, created_at, updated_at)
      VALUES ('#{id}', '#{name}', #{position}, true, now(), now())
      """
    end

    # Built-in roles are always present: they cannot be deleted, renamed or made custom.
    execute """
    CREATE FUNCTION protect_built_in_roles() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'built-in role % cannot be deleted', OLD.name
          USING ERRCODE = 'restrict_violation';
      END IF;
      IF NEW.name <> OLD.name OR NOT NEW.built_in THEN
        RAISE EXCEPTION 'built-in role % cannot be renamed or made custom', OLD.name
          USING ERRCODE = 'restrict_violation';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER roles_protect_built_in
    BEFORE UPDATE OR DELETE ON roles
    FOR EACH ROW WHEN (OLD.built_in)
    EXECUTE FUNCTION protect_built_in_roles()
    """
  end

  def down do
    drop table(:user_roles)
    drop table(:roles)
    execute "DROP FUNCTION protect_built_in_roles()"
  end
end

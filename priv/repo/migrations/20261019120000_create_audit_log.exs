# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateAuditLog do
  use Ecto.Migration

  def up do
    # SP-06, MVP §6. admin_id is null for changes made from the command line (AD-09).
    # Users are never hard-deleted (AC-07 anonymises), so the reference restricts.
    create table(:audit_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :admin_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :change, :string, null: false
      add :before, :map
      add :after, :map

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:audit_log, [:created_at])
    create index(:audit_log, [:admin_id])

    # The log is append-only: rows can be added, never changed or removed.
    execute """
    CREATE FUNCTION audit_log_append_only() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'audit_log is append-only' USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER audit_log_append_only
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_append_only()
    """

    execute """
    CREATE TRIGGER audit_log_no_truncate
    BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION audit_log_append_only()
    """
  end

  def down do
    drop table(:audit_log)
    execute "DROP FUNCTION audit_log_append_only()"
  end
end

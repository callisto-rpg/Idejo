# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateModActions do
  use Ecto.Migration

  # MO-03, MVP §6: the moderation log, one row per moderator action, with moderator, target,
  # reason and time. Append-only like audit_log. target_id and category_id are plain ids,
  # not references: a deleted category or message must not change the log.
  def up do
    create table(:mod_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :moderator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :action, :string, null: false
      add :target_type, :string, null: false
      add :target_id, :binary_id, null: false
      # The category the target was in, for showing moderators the actions in their categories.
      add :category_id, :binary_id
      add :reason, :text
      add :details, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:mod_actions, [:created_at])
    create index(:mod_actions, [:category_id, :created_at])
    create index(:mod_actions, [:target_type, :target_id])

    execute """
    CREATE FUNCTION mod_actions_append_only() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'mod_actions is append-only' USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER mod_actions_append_only
    BEFORE UPDATE OR DELETE ON mod_actions
    FOR EACH ROW EXECUTE FUNCTION mod_actions_append_only()
    """

    execute """
    CREATE TRIGGER mod_actions_no_truncate
    BEFORE TRUNCATE ON mod_actions
    FOR EACH STATEMENT EXECUTE FUNCTION mod_actions_append_only()
    """
  end

  def down do
    drop table(:mod_actions)
    execute "DROP FUNCTION mod_actions_append_only()"
  end
end

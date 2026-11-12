# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddMessagesChangeSeq do
  use Ecto.Migration

  # AP-16 (steward decision, 2026-11-10): every message change gets the next value of one
  # sequence, in commit order within its topic: the trigger first takes a transaction lock
  # on the topic (pg_advisory_xact_lock), so a value handed out later is never committed
  # earlier. Rows written before this migration have none (null): older than any cursor.
  # Adding a nullable column without a default changes only the catalogue (no rewrite).
  def up do
    execute "CREATE SEQUENCE IF NOT EXISTS message_change_seq"

    alter table(:messages) do
      add :change_seq, :bigint
    end

    execute """
    CREATE OR REPLACE FUNCTION messages_change_seq() RETURNS trigger AS $$
    BEGIN
      PERFORM pg_advisory_xact_lock(hashtextextended(NEW.topic_id::text, 1617));
      NEW.change_seq := nextval('message_change_seq');
      RETURN NEW;
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER messages_change_seq BEFORE INSERT OR UPDATE ON messages
    FOR EACH ROW EXECUTE FUNCTION messages_change_seq()
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS messages_change_seq ON messages"
    execute "DROP FUNCTION IF EXISTS messages_change_seq()"

    alter table(:messages) do
      remove :change_seq
    end

    execute "DROP SEQUENCE IF EXISTS message_change_seq"
  end
end

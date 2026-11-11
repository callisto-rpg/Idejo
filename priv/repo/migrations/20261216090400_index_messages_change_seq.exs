# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.IndexMessagesChangeSeq do
  use Ecto.Migration

  # AP-16: a topic's changes since a cursor, and its current cursor, read from one index.
  # Built concurrently, so a large messages table stays writable meanwhile.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:messages, [:topic_id, :change_seq], concurrently: true)
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateWarnings do
  use Ecto.Migration

  # MO-02 "warn" (steward request, 2026-11-09): a moderator warns a message's author, with a
  # reason. The warned member sees each warning in a card until they acknowledge it
  # (`seen_at`); `users.warning_pending` says, with no query, that one waits.
  def change do
    create table(:warnings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :moderator_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      # Plain id, as the moderation log's: who may see the warning follows the category.
      add :category_id, :binary_id
      add :reason, :text, null: false
      add :seen_at, :utc_datetime

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create index(:warnings, [:user_id, :created_at])
    create index(:warnings, [:moderator_id])
    create index(:warnings, [:message_id])

    alter table(:users) do
      add :warning_pending, :boolean, null: false, default: false
    end
  end
end

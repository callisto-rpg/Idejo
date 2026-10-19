# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateMessageVersions do
  use Ecto.Migration

  # Growing messages (GM, MVP §6 as changed with the steward): every commit overwrites the
  # message's full text, written before it is acknowledged (NF-02). Only a commit that changes
  # text already sent keeps the previous full text here, with its time (GM-11); appends lose
  # nothing and keep no version.
  def change do
    create table(:message_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :body_md, :text, null: false

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create index(:message_versions, [:message_id, :created_at])

    # GM-09: at most one open message per author per topic.
    create unique_index(:messages, [:topic_id, :author_id],
             where: "state = 'open'",
             name: :messages_one_open_per_author
           )
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateFollows do
  use Ecto.Migration

  # TP-13, MVP §6: who follows which topic. Starting a topic or posting in it follows it; a
  # row with following = false keeps an explicit unfollow, so the next post does not undo it.
  def change do
    create table(:follows, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :topic_id, references(:topics, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :following, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
    end

    create index(:follows, [:topic_id], where: "following")
  end
end

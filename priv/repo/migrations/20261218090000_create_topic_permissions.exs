# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateTopicPermissions do
  use Ecto.Migration

  # Topic permissions (steward request, 2026-11-13): one role's right on one topic, over its
  # category's. No row: the topic follows its category.
  def change do
    create table(:topic_permissions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :topic_id, references(:topics, type: :binary_id, on_delete: :delete_all), null: false
      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all), null: false
      add :right, :string, null: false
      add :effect, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:topic_permissions, [:topic_id, :role_id, :right])
    create index(:topic_permissions, [:right, :topic_id])
    create index(:topic_permissions, [:role_id])
  end
end

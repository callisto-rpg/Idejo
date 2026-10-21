# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddDeletedToMessages do
  use Ecto.Migration

  # MO-02: a message deleted by a moderator stays, with its text and versions kept for
  # moderators (steward decision); readers see a placeholder.
  def change do
    alter table(:messages) do
      add :deleted_at, :utc_datetime_usec
      add :deleted_by_id, references(:users, type: :binary_id, on_delete: :restrict)
    end
  end
end

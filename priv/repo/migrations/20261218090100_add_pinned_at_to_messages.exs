# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddPinnedAtToMessages do
  use Ecto.Migration

  # Pinned messages (steward request, 2026-11-13): listed in the topic navigator.
  def change do
    alter table(:messages) do
      add :pinned_at, :utc_datetime_usec
    end

    create index(:messages, [:topic_id, :pinned_at], where: "pinned_at IS NOT NULL")
  end
end

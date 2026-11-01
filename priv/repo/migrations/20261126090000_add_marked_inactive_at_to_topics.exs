# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddMarkedInactiveAtToTopics do
  use Ecto.Migration

  # Inactive topics (steward decision, 2026-11-01): when an administrator marked the topic
  # inactive from the topic menu. It stays inactive until a message is sent there
  # (`last_activity_at` passes this).
  def change do
    alter table(:topics) do
      add :marked_inactive_at, :utc_datetime_usec
    end
  end
end

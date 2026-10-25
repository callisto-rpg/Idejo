# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddFollowedStateToPushPreferences do
  use Ecto.Migration

  # PN-04: when the last "new messages in N topics you follow" went, and its N.
  def change do
    alter table(:push_preferences) do
      add :followed_sent_at, :utc_datetime_usec
      add :followed_count, :integer, null: false, default: 0
    end
  end
end

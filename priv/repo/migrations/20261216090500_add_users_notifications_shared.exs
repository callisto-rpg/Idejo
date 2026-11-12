# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddUsersNotificationsShared do
  use Ecto.Migration

  # Steward request, 2026-11-13 (Idejo.Community.SharedSettings): on a forum, the member's
  # email and push choices come from the group's inbox and are not changed here; on the
  # inbox, the member chose to send theirs to every forum.
  def change do
    alter table(:users) do
      add :notifications_shared, :boolean, null: false, default: false
    end
  end
end

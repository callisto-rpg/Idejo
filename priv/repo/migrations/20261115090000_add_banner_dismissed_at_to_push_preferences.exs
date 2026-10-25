# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddBannerDismissedAtToPushPreferences do
  use Ecto.Migration

  # PN-20: "Not now" on the notifications banner, kept on the server so it follows the user.
  def change do
    alter table(:push_preferences) do
      add :banner_dismissed_at, :utc_datetime_usec
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddMentionSettingsToRoles do
  use Ecto.Migration

  # TP-10 role mentions (+role; steward decision, 2026-10-22), two settings per role:
  # - mentionable: everyone may notify its members with +role;
  # - mentions_below: its members may notify any role ranked below it.
  # Both on for owner, administrator and moderator out of the box; member and guest never.
  def change do
    alter table(:roles) do
      add :mentionable, :boolean, null: false, default: false
      add :mentions_below, :boolean, null: false, default: false
    end

    execute(
      """
      UPDATE roles SET mentionable = true, mentions_below = true
      WHERE built_in AND name IN ('owner', 'administrator', 'moderator')
      """,
      ""
    )
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddSelfSelectAndWelcome do
  use Ecto.Migration

  # Steward decision, 2026-10-23: owners and administrators mark custom roles "self select",
  # which members give themselves; a welcome card (roles, Rules, About) shows once, on a new
  # member's first visit. Members who joined before see no card.
  def change do
    alter table(:roles) do
      add :self_select, :boolean, null: false, default: false
    end

    alter table(:users) do
      add :welcomed_at, :utc_datetime
    end

    execute "UPDATE users SET welcomed_at = now()", ""
  end
end

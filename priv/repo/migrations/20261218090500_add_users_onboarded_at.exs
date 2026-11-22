# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddUsersOnboardedAt do
  use Ecto.Migration

  # The onboarding tour (steward request, 2026-11-22): shown until this is set. Members who
  # joined before it have joined already: theirs is set now.
  def up do
    alter table(:users) do
      add :onboarded_at, :utc_datetime
    end

    execute "UPDATE users SET onboarded_at = now()"
  end

  def down do
    alter table(:users) do
      remove :onboarded_at
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddBanToUsers do
  use Ecto.Migration

  # MO-02: a banned account cannot sign in, permanently (banned_until null) or until a time.
  # Who banned it and why are in the moderation log (MO-03).
  def change do
    alter table(:users) do
      add :banned_at, :utc_datetime_usec
      add :banned_until, :utc_datetime_usec
    end
  end
end

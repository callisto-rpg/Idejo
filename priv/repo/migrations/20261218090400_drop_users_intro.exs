# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.DropUsersIntro do
  use Ecto.Migration

  # The getting-started card is gone (steward request, 2026-11-22).
  def change do
    alter table(:users) do
      remove :intro_pending, :boolean, default: false, null: false
      remove :intro_hidden, :boolean, default: false, null: false
    end
  end
end

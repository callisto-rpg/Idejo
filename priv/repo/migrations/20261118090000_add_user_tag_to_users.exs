# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddUserTagToUsers do
  use Ecto.Migration

  # The user tag (steward decision, 2026-10-27): optional free text shown after the name.
  def change do
    alter table(:users) do
      add :user_tag, :string, size: 32
    end
  end
end

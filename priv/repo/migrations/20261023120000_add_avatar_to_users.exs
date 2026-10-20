# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddAvatarToUsers do
  use Ecto.Migration

  # AC-04, MVP §6: a user's avatar, an upload (TP-12) stored as a 256 px WebP square.
  def change do
    alter table(:users) do
      add :avatar_id, references(:uploads, type: :binary_id, on_delete: :nilify_all)
    end
  end
end

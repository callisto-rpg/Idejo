# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddDarkAvatarToUsers do
  use Ecto.Migration

  # Steward decision, 2026-10-23: an optional second avatar, shown with the dark theme; like
  # the avatar (AC-04), an upload stored as a 256 px WebP square.
  def change do
    alter table(:users) do
      add :avatar_dark_id, references(:uploads, type: :binary_id, on_delete: :nilify_all)
    end
  end
end

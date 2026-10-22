# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddIconAndColourToCategories do
  use Ecto.Migration

  # RP-03 (steward decision, 2026-10-23): a category may have an icon (an id from
  # Idejo.Forum.CategoryIcons) and a colour (#rrggbb). Without them it keeps its initial on a
  # tint picked from its id.
  def change do
    alter table(:categories) do
      add :icon, :string
      add :colour, :string
    end
  end
end

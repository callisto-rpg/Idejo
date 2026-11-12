# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddUploadsDimensions do
  use Ecto.Migration

  # AP-11 (steward decision, 2026-11-10): an image's size in pixels, for the app to lay it
  # out before it loads. Known for images uploaded from now on; older ones have none.
  def change do
    alter table(:uploads) do
      add :width, :integer
      add :height, :integer
    end
  end
end

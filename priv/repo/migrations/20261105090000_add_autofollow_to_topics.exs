# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddAutofollowToTopics do
  use Ecto.Migration

  # Steward decision, 2026-10-23: administrators mark topics "followed by everyone"; every
  # user who may view one follows it unless they unfollowed it, and visitors see it followed.
  def change do
    alter table(:topics) do
      add :autofollow, :boolean, null: false, default: false
    end
  end
end

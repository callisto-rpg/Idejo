# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.GraphicalComposerOnForNewUsers do
  @moduledoc """
  "Use the graphical composer" is on for new accounts (steward decision, 2026-11-03).
  Existing members keep the choice they have.
  """
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :graphical_composer, :boolean,
        null: false,
        default: true,
        from: {:boolean, null: false, default: false}
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddSpoilerLabelToMessages do
  use Ecto.Migration

  # `!spoiler:overlay text:` (steward decision, 2026-10-28): what the cover says.
  def change do
    alter table(:messages) do
      add :spoiler_label, :string, size: 100
    end
  end
end

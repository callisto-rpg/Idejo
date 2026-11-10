# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddMessagesImportSource do
  use Ecto.Migration

  # The inbox (steward request, 2026-11-10): a message copied from another forum's private
  # conversation, "<host>/<message id>", copied once.
  def change do
    alter table(:messages) do
      add :import_source, :string
    end

    create unique_index(:messages, [:import_source], where: "import_source IS NOT NULL")
  end
end

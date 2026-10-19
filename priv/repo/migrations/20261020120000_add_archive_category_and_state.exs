# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddArchiveCategoryAndState do
  use Ecto.Migration

  # RP-03, TP-14: deleting a category can archive its topics. They go, read-only, to the
  # Archive category: one built-in category (archive = true), made the first time something is
  # archived and hidden from every role until an administrator opens it in the permission grid.
  def up do
    alter table(:categories) do
      add :archive, :boolean, null: false, default: false
    end

    create unique_index(:categories, [:archive], where: "archive", name: :categories_one_archive)

    drop constraint(:topics, :state_valid)
    create constraint(:topics, :state_valid, check: "state IN ('open', 'locked', 'archived')")
  end

  def down do
    drop constraint(:topics, :state_valid)
    create constraint(:topics, :state_valid, check: "state IN ('open', 'locked')")

    drop index(:categories, [:archive], name: :categories_one_archive)

    alter table(:categories) do
      remove :archive
    end
  end
end

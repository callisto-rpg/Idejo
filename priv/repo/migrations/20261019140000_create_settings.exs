# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  # AD-02, MVP §6. Values are stored as text and typed by Idejo.Settings; a missing key
  # means the default applies.
  def change do
    create table(:settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :text, null: false

      timestamps(type: :utc_datetime)
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  # AC-09: one row per OpenID Connect link, keyed on the provider's issuer and its subject
  # for the person, never on email. No tokens are stored. Deleting an account (AC-07) deletes
  # its rows itself (users are anonymised, not deleted); the cascade covers anything else.
  def change do
    create table(:user_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :issuer, :string, null: false
      add :subject, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:user_identities, [:issuer, :subject])
    create index(:user_identities, [:user_id])
  end
end

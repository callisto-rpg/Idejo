# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddBioToUsers do
  use Ecto.Migration

  # AC-04: the bio, shown on the user page under the roles; Markdown and its sanitised HTML
  # (FD-03).
  def change do
    alter table(:users) do
      add :bio_md, :text
      add :bio_html, :text
    end
  end
end

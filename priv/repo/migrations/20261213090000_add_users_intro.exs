# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddUsersIntro do
  use Ecto.Migration

  # The getting-started card (steward request, 2026-11-09): shown after each sign-in
  # (`intro_pending`) until closed, never again once its member chose "Close and hide this in
  # the future" (`intro_hidden`). Stored with the account, so no update brings it back.
  def change do
    alter table(:users) do
      add :intro_pending, :boolean, null: false, default: false
      add :intro_hidden, :boolean, null: false, default: false
    end
  end
end

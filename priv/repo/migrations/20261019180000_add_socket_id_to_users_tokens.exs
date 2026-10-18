# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddSocketIdToUsersTokens do
  use Ecto.Migration

  # SP-02: one id per signed-in browser session, kept when its token is reissued, so signing
  # out or resetting the password (AC-02) disconnects every LiveView of the session.
  def change do
    alter table(:users_tokens) do
      add :socket_id, :string
    end
  end
end

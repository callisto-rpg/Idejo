# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.CreateVapidKeys do
  use Ecto.Migration

  # PN-14: the server's VAPID key pair for web push, made once on every install. Migrations
  # run before the setup wizard, so a new install has one too. Kept when already there (a
  # restored backup's).
  def up do
    execute(fn ->
      %{rows: [[present]]} =
        repo().query!(
          "SELECT count(*) FROM settings WHERE key IN ('vapid_public_key', 'vapid_private_key')"
        )

      if present == 0 do
        for row <- Idejo.Push.Vapid.rows(Idejo.Push.Vapid.generate(), DateTime.utc_now(:second)) do
          repo().query!(
            "INSERT INTO settings (key, value, inserted_at, updated_at) VALUES ($1, $2, $3, $3)",
            [row.key, row.value, row.inserted_at]
          )
        end
      end
    end)
  end

  def down do
    execute("DELETE FROM settings WHERE key IN ('vapid_public_key', 'vapid_private_key')")
  end
end

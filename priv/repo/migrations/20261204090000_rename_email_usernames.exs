# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.RenameEmailUsernames do
  use Ecto.Migration

  # AC-09 (steward decision, 2026-11-06): accounts named after their email are renamed
  # (Idejo.Accounts.UsernamePrivacy). Not undone.
  def up do
    flush()
    Idejo.Accounts.UsernamePrivacy.rename_all()
  end

  def down, do: :ok
end

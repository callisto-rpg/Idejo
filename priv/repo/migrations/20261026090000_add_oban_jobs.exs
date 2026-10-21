# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddObanJobs do
  use Ecto.Migration

  # Oban's job queue (AD-05: the nightly backup is its first job). Pinned to a version, so
  # upgrading Oban never changes what this migration does.
  def up, do: Oban.Migrations.up(version: 14)

  def down, do: Oban.Migrations.down(version: 1)
end

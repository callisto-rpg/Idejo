# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddMutedToFollows do
  use Ecto.Migration

  # Steward decision, 2026-10-23: "Unfollow & mute" from a topic's menu. A muted topic
  # notifies nothing, even an @ or + mention, until the user follows it again.
  def change do
    alter table(:follows) do
      add :muted, :boolean, null: false, default: false
    end
  end
end

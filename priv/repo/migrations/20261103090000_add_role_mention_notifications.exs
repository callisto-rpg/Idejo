# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddRoleMentionNotifications do
  use Ecto.Migration

  # Steward decision, 2026-10-23: a +role mention notifies as "role_mention", told apart from
  # an @mention (the sidebar's blue dot). Earlier role mentions stay "mention".
  def up do
    drop constraint(:notifications, :kind)

    create constraint(:notifications, :kind,
             check: "kind IN ('mention', 'role_mention', 'reply', 'follow', 'reaction')"
           )
  end

  def down do
    execute "UPDATE notifications SET kind = 'mention' WHERE kind = 'role_mention'"
    drop constraint(:notifications, :kind)

    create constraint(:notifications, :kind,
             check: "kind IN ('mention', 'reply', 'follow', 'reaction')"
           )
  end
end

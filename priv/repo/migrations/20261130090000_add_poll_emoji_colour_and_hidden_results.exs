# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddPollEmojiColourAndHiddenResults do
  use Ecto.Migration

  # Polls (steward decision, 2026-11-02): an emoji and a bar colour per answer (none: the
  # theme's), results hidden until the poll closes, and automessages that post a poll.
  def change do
    alter table(:poll_options) do
      add :emoji, :string
      add :colour, :string
    end

    alter table(:polls) do
      add :hide_results, :boolean, null: false, default: false
    end

    alter table(:automessages) do
      add :poll, :map
    end
  end
end

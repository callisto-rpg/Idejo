# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddTopicsMovedToChat do
  use Ecto.Migration

  # Private conversations handed to the chat service (steward request, 2026-11-10): the
  # service copied them, so the forum no longer lists or opens them, and sends their
  # participants there. The rows stay, for moderators' reports and the participants' data.
  def change do
    alter table(:topics) do
      add :moved_to_chat_at, :utc_datetime_usec
    end
  end
end

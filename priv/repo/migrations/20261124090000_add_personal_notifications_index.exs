# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddPersonalNotificationsIndex do
  use Ecto.Migration

  # A user's mentions and replies, for the header's count on every page
  # (`Idejo.Reading.for_you/1`) and push counts (PN-01 to PN-03). Following a topic adds a
  # `follow` row at each of its new messages, so these are a small part of a user's
  # notifications, and without this index each count read every follow row too, more as
  # they pile up. Only rows of these kinds are indexed, so writing follow rows costs no more.
  def change do
    create index(:notifications, [:user_id, :message_id],
             where: "kind IN ('mention', 'reply', 'role_mention')",
             name: :notifications_personal_index
           )
  end
end

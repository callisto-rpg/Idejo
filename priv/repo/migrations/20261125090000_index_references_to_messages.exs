# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.IndexReferencesToMessages do
  use Ecto.Migration

  # Deleting a topic (Forum.delete_topic/3) deletes its messages by the foreign keys'
  # cascades, and each deleted message makes PostgreSQL look up what refers to it. Without
  # an index on the referring column, each look-up reads the whole table: a topic of 2,000
  # messages took 42 s on a test server of 200,000 messages, past the 15 s a request may
  # take, so it could not be deleted at all. With these, 1 s.
  def change do
    # Only replies have one, and it never changes once written: nothing more to keep up.
    create index(:messages, [:reply_to_id],
             where: "reply_to_id IS NOT NULL",
             name: :messages_reply_to_id_index
           )

    create index(:notifications, [:message_id])
  end
end

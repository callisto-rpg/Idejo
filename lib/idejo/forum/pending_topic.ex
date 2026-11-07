# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.PendingTopic do
  @moduledoc """
  MO-04: a new topic waiting for a moderator's approval, as its author wrote it: the title,
  the first message's Markdown, the chosen tags and the message it was started from (TP-09),
  if any. Approved, it becomes a topic (`Idejo.Forum.approve_topic/2`) and this row goes;
  rejected, the row goes. Only its author and the category's moderators see it.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pending_topics" do
    belongs_to :category, Idejo.Forum.Category
    belongs_to :author, Idejo.Accounts.User
    field :title, :string
    field :body, :string
    field :tag_ids, {:array, :string}, default: []
    belongs_to :forked_from, Idejo.Messages.Message, foreign_key: :forked_from_message_id

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end

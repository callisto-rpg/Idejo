# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.MessageMove do
  @moduledoc """
  TP-15: messages a moderator moved out of a topic (steward request, 2026-11-14), shown as a
  banner under `after_message_id`, the message before the oldest of them, with how many went
  and a link to `target_topic_id`. None when the moderator unticked "Leave a banner".
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "message_moves" do
    belongs_to :source_topic, Idejo.Forum.Topic
    belongs_to :after_message, Idejo.Messages.Message
    belongs_to :target_topic, Idejo.Forum.Topic
    field :count, :integer
    field :new_topic, :boolean, default: false
    field :moved_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}
end

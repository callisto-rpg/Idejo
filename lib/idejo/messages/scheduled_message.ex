# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.ScheduledMessage do
  @moduledoc """
  A message waiting to be posted (`!schedule`, steward decision, 2026-10-23): its text, the
  message it replies to and when it goes out. Only its author sees it until then
  (`Idejo.Messages.Scheduling`).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "scheduled_messages" do
    field :body_md, :string
    field :post_at, :utc_datetime_usec
    belongs_to :topic, Idejo.Forum.Topic
    belongs_to :author, Idejo.Accounts.User
    belongs_to :reply_to, Idejo.Messages.Message

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Notifications.Notification do
  @moduledoc """
  An in-app notification (NO-01): a message that mentions the user, replies to them, or was
  posted in a topic they follow. One per user and message (NO-02).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "notifications" do
    field :kind, :string
    field :read_at, :utc_datetime_usec
    belongs_to :user, Idejo.Accounts.User
    belongs_to :message, Idejo.Messages.Message
    # TP-17: for a "reaction" notification, how many reactions the message has, set by
    # `Idejo.Notifications.list/2`.
    field :reactions, :integer, virtual: true

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end
end

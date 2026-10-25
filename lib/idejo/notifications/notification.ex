# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Notifications.Notification do
  @moduledoc """
  An in-app notification (NO-01): a message that mentions the user (`mention`), replies to
  them (`reply`), mentions one of their roles (`role_mention`) or was posted in a topic they
  follow (`follow`). One per user and message (NO-02). Rows of kind `reaction` are from
  before reactions stopped notifying (2026-10-23).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "notifications" do
    field :kind, :string
    field :read_at, :utc_datetime_usec
    # PN-05: when it was pushed; a notification is pushed at most once.
    field :pushed_at, :utc_datetime_usec
    belongs_to :user, Idejo.Accounts.User
    belongs_to :message, Idejo.Messages.Message

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end
end

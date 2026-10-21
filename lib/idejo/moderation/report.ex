# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Moderation.Report do
  @moduledoc """
  A report of a message (MO-01): who reported it, why, and whether a moderator has resolved
  or dismissed it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "reports" do
    field :reason, :string
    field :status, :string, default: "open"
    field :handled_at, :utc_datetime_usec
    belongs_to :message, Idejo.Messages.Message
    belongs_to :reporter, Idejo.Accounts.User
    belongs_to :handled_by, Idejo.Accounts.User

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @doc "A changeset for the report form: the reason, required, at most 1,000 characters."
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:reason])
    |> update_change(:reason, &(&1 && String.trim(&1)))
    |> validate_required([:reason])
    |> validate_length(:reason, max: 1000)
    |> unique_constraint([:message_id, :reporter_id],
      name: :reports_one_open_per_reporter,
      message: "you have already reported this message"
    )
  end
end

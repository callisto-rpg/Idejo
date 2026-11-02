# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.PollOption do
  @moduledoc """
  One answer of a poll (`Idejo.Messages.Poll`), in the order its author gave, with an
  optional emoji (an `Idejo.Emoji` name) and bar colour (`#rrggbb`; none: the theme's
  primary colour). Steward decision, 2026-11-02.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "poll_options" do
    field :position, :integer
    field :text, :string
    field :emoji, :string
    field :colour, :string
    belongs_to :poll, Idejo.Messages.Poll
  end
end

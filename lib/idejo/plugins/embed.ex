# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Plugins.Embed do
  @moduledoc """
  What a plugin added under a message (`Idejo.Plugins.attach/4`). `block` is the kind
  (`video`, `iframe`, `button`, `card`) and `data` what it shows, checked when stored:
  `video` and `iframe` an https `src`; `button` a `label` and an http(s) `url`; `card` a
  `label` with `body_md` and its sanitised `body_html` (FD-03).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "message_embeds" do
    field :plugin, :string
    field :block, :string
    field :data, :map, default: %{}
    belongs_to :message, Idejo.Messages.Message

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end
end

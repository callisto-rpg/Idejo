# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Plugins.Setting do
  @moduledoc "A plugin's settings, by command: on or off, and the roles that may use it."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:command, :string, autogenerate: false}
  schema "plugin_settings" do
    field :enabled, :boolean, default: false
    field :role_ids, {:array, Ecto.UUID}, default: []

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end
end

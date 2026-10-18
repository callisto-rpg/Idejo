# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Settings.Setting do
  @moduledoc """
  One stored server-wide setting (AD-02). See `Idejo.Settings` for the known keys.
  """
  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "settings" do
    field :value, :string

    timestamps(type: :utc_datetime)
  end
end

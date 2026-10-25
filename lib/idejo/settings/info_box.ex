# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Settings.InfoBox do
  @moduledoc """
  An info box (steward decision, 2026-10-25): a card beside the home page's categories,
  drawn like theirs, holding whatever the administrators write. A title, an icon
  (`Idejo.Forum.CategoryIcons`) and a colour (`#rrggbb`) like a category's, and Markdown
  text stored with its sanitised HTML (FD-03). Ordered by `position`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Idejo.Forum.CategoryIcons

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  schema "info_boxes" do
    field :title, :string
    field :icon, :string
    field :colour, :string
    field :body_md, :string, default: ""
    field :body_html, :string, default: ""
    field :position, :integer

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  A changeset for an info box's title, look and text. The caller sets the position and,
  once it is valid, the HTML.
  """
  def changeset(box, attrs) do
    box
    |> cast(attrs, [:title, :icon, :colour, :body_md])
    |> update_change(:title, &(&1 && String.trim(&1)))
    # An emptied text is cast to nil; the column keeps "" instead.
    |> then(&if(get_field(&1, :body_md), do: &1, else: put_change(&1, :body_md, "")))
    |> validate_required([:title])
    |> validate_length(:title, max: 80)
    |> update_change(:colour, &(&1 && &1 |> String.trim() |> String.downcase()))
    |> validate_format(:colour, ~r/^#[0-9a-f]{6}$/, message: "must look like #3366ff")
    |> validate_change(:icon, fn :icon, icon ->
      if CategoryIcons.icon?(icon), do: [], else: [icon: "is not one of the icons"]
    end)
  end
end

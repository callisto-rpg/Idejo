# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Settings.InfoBox do
  @moduledoc """
  An info box (steward decision, 2026-10-25): a card beside the home page's categories,
  drawn like theirs, holding whatever the administrators write. A title, an icon
  (`Idejo.Forum.CategoryIcons`) and a colour (`#rrggbb`) like a category's, and Markdown
  text stored with its sanitised HTML (FD-03). Ordered by `position`.

  Its place (steward request, 2026-11-13): `placement` `"before"` (a row of its own above
  every section of categories), `"first"` (the first section, as before), `"group"` (the
  section of the category group `group_id`) or `"other"` (the categories without a group);
  `at_end`, after that section's categories rather than before them. A section that is not
  shown (no category there the reader may view, or its group deleted) gives the first.
  The form sets both through `place` (`"before"`, `"first"`, `"other"`, `"group:<id>"`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Idejo.Forum.{CategoryGroup, CategoryIcons}

  @placements ~w(before first group other)

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  schema "info_boxes" do
    field :title, :string
    field :icon, :string
    field :colour, :string
    field :body_md, :string, default: ""
    field :body_html, :string, default: ""
    field :position, :integer
    # Off, the home page shows the text alone, without the icon and title (steward
    # decision, 2026-10-26).
    field :show_head, :boolean, default: true
    field :placement, :string, default: "first"
    belongs_to :group, CategoryGroup, type: Ecto.UUID
    field :at_end, :boolean, default: false
    # The form's one choice of place, made into `placement` and `group_id`.
    field :place, :string, virtual: true

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  A changeset for an info box's title, look and text. The caller sets the position and,
  once it is valid, the HTML.
  """
  def changeset(box, attrs) do
    box
    |> cast(attrs, [:title, :icon, :colour, :body_md, :show_head, :at_end, :place])
    |> put_place()
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
    |> validate_inclusion(:placement, @placements)
    |> foreign_key_constraint(:group_id)
  end

  @doc "The form's value for a box's place (`place`)."
  @spec place(t()) :: String.t()
  def place(%__MODULE__{placement: "group", group_id: id}) when is_binary(id), do: "group:" <> id
  def place(%__MODULE__{placement: "group"}), do: "first"
  def place(%__MODULE__{placement: placement}), do: placement

  defp put_place(changeset) do
    case get_change(changeset, :place) do
      nil ->
        put_change(changeset, :place, place(changeset.data))

      "group:" <> id ->
        case Ecto.UUID.cast(id) do
          {:ok, id} -> change(changeset, placement: "group", group_id: id)
          :error -> add_error(changeset, :place, "is not one of the places")
        end

      place when place in ~w(before first other) ->
        change(changeset, placement: place, group_id: nil)

      _place ->
        add_error(changeset, :place, "is not one of the places")
    end
  end
end

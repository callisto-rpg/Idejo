# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin do
  @moduledoc """
  Helpers shared by the admin panel LiveViews (AD-02).
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext

  import IdejoWeb.CoreComponents, only: [input: 1]

  alias Idejo.Access.Role
  alias Idejo.Forum.CategoryIcons
  alias IdejoWeb.{CategoryIconNames, TopicComponents}

  @doc """
  The name of a role as shown to people: built-in roles are translated, custom roles
  keep the name their admin gave them.
  """
  @spec role_name(Role.t()) :: String.t()
  def role_name(%Role{built_in: true, name: "owner"}), do: gettext("Owner")
  def role_name(%Role{built_in: true, name: "administrator"}), do: gettext("Administrator")
  def role_name(%Role{built_in: true, name: "moderator"}), do: gettext("Moderator")
  def role_name(%Role{built_in: true, name: "member"}), do: gettext("Member")
  def role_name(%Role{built_in: true, name: "guest"}), do: gettext("Guest")
  def role_name(%Role{name: name}), do: name

  @doc """
  A role's name in the role's colour, grey when it has none (steward decision, 2026-10-23).
  The colour is the `--role` of the `role-{id}` class, set by `IdejoWeb.Layouts.role_colours/1`
  in the page's head and, on admin pages, by the `RoleColours` hook from `data-role-colour`,
  so a colour just changed shows at once: the content security policy refuses style
  attributes.
  """
  attr :role, Role, required: true
  attr :class, :any, default: nil

  def role_label(assigns) do
    assigns = assign(assigns, :name, role_name(assigns.role))

    ~H"""
    <span class={["role-name", "role-#{@role.id}", @class]} data-role-colour={@role.colour}>{@name}</span>
    """
  end

  @doc """
  A user's name in their name colour (RP-06: the highest-ranked role that has one), or as
  plain text. Takes the user's roles from `Idejo.Access.roles_of/1`.
  """
  attr :roles, :list, required: true
  slot :inner_block, required: true

  def coloured_name(assigns) do
    assigns = assign(assigns, :role, Idejo.Access.name_role(assigns.roles))

    ~H"""
    <span
      class={@role && ["name-colour", "role-#{@role.id}"]}
      data-role-colour={@role && @role.colour}
    >{render_slot(@inner_block)}</span>
    """
  end

  attr :form, :any, required: true
  attr :id, :string, required: true
  attr :item_id, :any, required: true, doc: "the category's or info box's id, nil when new"
  attr :name_field, :atom, default: :name, doc: "the field whose initial the mark shows"

  @doc """
  The colour (typed, or picked with the browser's colour picker) and the icon of a category
  (RP-03) or an info box (steward decision, 2026-10-25), with a preview of the mark as it
  will show. The form's `phx-change` handler passes its params through `picked_colour/2`.
  """
  def look(assigns) do
    form = assigns.form
    colour = valid(form, :colour)
    tint = if assigns.item_id, do: CategoryIcons.tint(assigns.item_id), else: "#6567e7"

    preview = %{
      id: assigns.item_id || "new",
      name: blank_to_nil(form[assigns.name_field].value) || "?",
      icon: valid(form, :icon),
      colour: colour
    }

    assigns =
      assign(assigns,
        preview: preview,
        tile: colour || tint,
        icon: form[:icon].value || ""
      )

    ~H"""
    <div class="category-look">
      <div class="category-look-preview" aria-hidden="true">
        <TopicComponents.category_mark category={@preview} size={:large} />
      </div>
      <div class="category-look-colour">
        <.input
          field={@form[:colour]}
          type="text"
          label={gettext("Colour (#rrggbb, empty for the default)")}
          placeholder="#3366ff"
          spellcheck="false"
        />
        <label class="category-look-picker">
          <span class="sr-only">{gettext("Pick a colour")}</span>
          <input
            type="color"
            name={@form[:colour_picker].name}
            id={"#{@id}-colour-picker"}
            value={@tile}
          />
        </label>
      </div>
    </div>
    <fieldset class="icon-picker">
      <legend class="label mb-1">{gettext("Icon")}</legend>
      <label class="icon-choice icon-choice-none">
        <input type="radio" name={@form[:icon].name} value="" checked={@icon == ""} />
        <span>{gettext("No icon")}</span>
      </label>
      <fieldset :for={{group, ids} <- CategoryIcons.groups()} class="icon-group">
        <legend>{CategoryIconNames.group_name(group)}</legend>
        <div class="icon-choices">
          <label :for={id <- ids} class="icon-choice" title={CategoryIconNames.name(id)}>
            <input type="radio" name={@form[:icon].name} value={id} checked={@icon == id} />
            <svg viewBox="0 0 32 32" aria-hidden="true" focusable="false">
              <TopicComponents.icon_shapes shapes={CategoryIcons.shapes(id, @tile)} />
            </svg>
            <span class="sr-only">{CategoryIconNames.name(id)}</span>
          </label>
        </div>
      </fieldset>
    </fieldset>
    """
  end

  @doc "The params of a `look/1` form, with the colour picker's choice in the hex field."
  @spec picked_colour(map(), map()) :: map()
  def picked_colour(params, %{"_target" => [_, "colour_picker"]}),
    do: Map.put(params, "colour", params["colour_picker"])

  def picked_colour(params, _all), do: params

  # A field's value only when it passed validation, for the preview.
  defp valid(form, field) do
    if Keyword.has_key?(form.errors, field), do: nil, else: blank_to_nil(form[field].value)
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end

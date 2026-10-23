# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin do
  @moduledoc """
  Helpers shared by the admin panel LiveViews (AD-02).
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Access.Role

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
end

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
  A small square in a role's colour, or nothing when it has none. Drawn as an SVG fill, not
  a style attribute: the content security policy refuses inline styles.
  """
  attr :colour, :string, default: nil

  def swatch(assigns) do
    ~H"""
    <svg :if={@colour} width="16" height="16" aria-hidden="true" class="inline-block align-middle">
      <rect width="16" height="16" rx="3" fill={@colour} />
    </svg>
    """
  end
end

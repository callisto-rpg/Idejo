# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicPermissionsHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.TopicPermissionsController`.
  """
  use IdejoWeb, :html

  embed_templates "topic_permissions_html/*"

  @doc "A right's name in the grid."
  @spec right_label(atom()) :: String.t()
  def right_label(:view), do: gettext("View")
  def right_label(:post), do: gettext("Post")
  def right_label(:moderate), do: gettext("Moderate")
  def right_label(:tag), do: gettext("Edit tags")

  @doc "A cell's name for screen readers: the right and the role."
  @spec cell_label(atom(), Idejo.Access.Role.t()) :: String.t()
  def cell_label(right, role),
    do: gettext("%{right} for %{role}", right: right_label(right), role: role.name)

  @doc """
  The choices of one cell: as the category has it (saying which), allow, deny. `inherited`
  is `:allow` or `:deny`.
  """
  @spec choices(:allow | :deny) :: [{String.t(), String.t()}]
  def choices(inherited) do
    [
      {if(inherited == :allow,
         do: gettext("As the category (allowed)"),
         else: gettext("As the category (not allowed)")
       ), "unset"},
      {gettext("Allow"), "allow"},
      {gettext("Deny"), "deny"}
    ]
  end

  @doc "A cell's current value: its own setting, else `\"unset\"`."
  @spec value(map(), Ecto.UUID.t(), atom()) :: String.t()
  def value(own, role_id, right), do: own |> Map.get({role_id, right}, :unset) |> Atom.to_string()
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin do
  @moduledoc """
  Helpers shared by the admin panel LiveViews (AD-02).
  """
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
end

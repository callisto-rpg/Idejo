# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserComponents do
  @moduledoc """
  The user card (TP-10): what an @mention leads to. Display name, username, picture and
  roles, on the page at `/u/{id}` and in the dialog a mention opens in a topic. A link to
  the full profile joins it when profiles are built.
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Access
  alias IdejoWeb.Admin

  @doc """
  Loads what the card shows: the user and their roles, highest first (RP-06), without the
  implicit guest.
  """
  @spec card_data(Idejo.Accounts.User.t()) :: map()
  def card_data(user) do
    roles = user |> Access.roles_of() |> Enum.reject(&(&1.built_in and &1.name == "guest"))
    %{user: user, roles: roles}
  end

  attr :card, :map, required: true, doc: "from `card_data/1`"
  attr :id, :string, default: "user-card"

  def user_card(assigns) do
    ~H"""
    <div id={"#{@id}-content"} class="flex items-start gap-4">
      <%!-- The profile picture arrives with avatars (AC-04); until then, an initial. --%>
      <div class="avatar avatar-placeholder" aria-hidden="true">
        <div class="bg-neutral text-neutral-content w-14 rounded-full">
          <span class="text-xl">{initial(@card.user)}</span>
        </div>
      </div>
      <div>
        <h2 id={"#{@id}-name"} class="text-lg font-semibold">{@card.user.display_name}</h2>
        <p class="opacity-70">@{@card.user.username}</p>
        <ul :if={@card.roles != []} class="mt-2 flex flex-wrap gap-2" aria-label={gettext("Roles")}>
          <li :for={role <- @card.roles} class="badge badge-sm gap-1">
            <Admin.swatch colour={role.colour} />
            {Admin.role_name(role)}
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp initial(user), do: user.display_name |> String.first() |> String.upcase()
end

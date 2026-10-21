# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserComponents do
  @moduledoc """
  The user card (TP-10): what an @mention leads to. Display name, username, picture and
  roles, on the page at `/u/{id}` and in the dialog a mention opens in a topic. A link to
  the full profile joins it when profiles are built.

  And the avatar (AC-04) wherever a user is shown: their picture, or their initial when they
  have none.
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Access
  alias Idejo.Uploads
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

  attr :heading, :string,
    values: ~w(h1 h2),
    default: "h2",
    doc: "h1 on the card's own page (AX-01), h2 in a dialog"

  def user_card(assigns) do
    ~H"""
    <div id={"#{@id}-content"} class="flex items-start gap-4">
      <.avatar user={@card.user} size={:large} />
      <div>
        <.dynamic_tag tag_name={@heading} id={"#{@id}-name"} class="text-lg font-semibold">
          {@card.user.display_name}
        </.dynamic_tag>
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

  @doc """
  A user's avatar (AC-04): their picture, or their initial on a plain circle. Decorative:
  the name is always shown next to it, so it has no text of its own for screen readers.
  """
  attr :user, :map, required: true
  attr :size, :atom, values: [:small, :medium, :large], default: :small

  def avatar(assigns) do
    assigns = assign(assigns, url: Uploads.avatar_url(assigns.user), box: box(assigns.size))

    ~H"""
    <span :if={@url} class="avatar shrink-0" aria-hidden="true">
      <span class={[@box, "rounded-full"]}><img src={@url} alt="" /></span>
    </span>
    <span :if={!@url} class="avatar avatar-placeholder shrink-0" aria-hidden="true">
      <span class={[@box, "rounded-full bg-neutral text-neutral-content"]}>
        <span>{initial(@user)}</span>
      </span>
    </span>
    """
  end

  defp box(:small), do: "w-6 text-xs"
  defp box(:medium), do: "w-12 text-lg"
  defp box(:large), do: "w-14 text-xl"

  defp initial(user), do: user.display_name |> String.first() |> String.upcase()
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserComponents do
  @moduledoc """
  The user card (TP-10): what an @mention leads to. Display name, username, picture and
  roles, on the page at `/u/{id}` and in the dialog a mention opens in a topic. A link to
  the full profile joins it when profiles are built. Server moderators also get a "User
  actions" button on it, with the moderation actions on the account (MO-02).

  And the avatar (AC-04) wherever a user is shown: their picture, or their initial when they
  have none.
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext
  use IdejoWeb, :verified_routes

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Uploads
  alias IdejoWeb.Admin

  @doc """
  Loads what the card shows to `viewer`: the user and their roles, highest first (RP-06),
  without the implicit guest, and the moderation actions the viewer may take on the account
  (`actions`, nil for everyone but server moderators).

  ## Options

    * `:return_to` - a topic path the ban forms come back to, when the card is in its dialog.
  """
  @spec card_data(Accounts.User.t(), Accounts.User.t() | nil, keyword()) :: map()
  def card_data(user, viewer \\ nil, opts \\ []) do
    roles = user |> Access.roles_of() |> Enum.reject(&(&1.built_in and &1.name == "guest"))
    %{user: user, roles: roles, actions: actions(viewer, user, opts[:return_to])}
  end

  # MO-02: only server moderators ban (Accounts.ban_user/4 checks it again), never themselves
  # and never a deleted account. Owners and administrators are shown, but cannot be banned.
  defp actions(nil, _user, _return_to), do: nil

  defp actions(viewer, user, return_to) do
    if viewer.id != user.id and user.status == "active" and Access.server_moderator?(viewer) do
      %{
        bannable?: not Access.administrator?(user),
        banned?: Accounts.banned?(user),
        return_to: return_to
      }
    end
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
          <li :for={role <- @card.roles} class="badge badge-sm">
            <Admin.role_label role={role} />
          </li>
        </ul>
        <.user_actions :if={@card[:actions]} user={@card.user} actions={@card.actions} />
      </div>
    </div>
    """
  end

  # MO-02: the "User actions" button and what it opens. A <details>, so it works from the
  # keyboard and without JavaScript; it opens in place, so the topic's dialog never clips it.
  # The forms post to BanController, which logs each action (MO-03).
  attr :user, :map, required: true
  attr :actions, :map, required: true

  defp user_actions(assigns) do
    ~H"""
    <div class="mt-3 space-y-2">
      <p :if={@actions.banned? and is_nil(@user.banned_until)} id="banned-state" class="text-sm">
        {gettext("Banned for good.")}
      </p>
      <p :if={@actions.banned? and @user.banned_until} id="banned-state" class="text-sm">
        {gettext("Banned until %{time}.",
          time: Calendar.strftime(@user.banned_until, "%Y-%m-%d %H:%M UTC")
        )}
      </p>
      <details id="user-actions">
        <summary class="btn btn-sm">{gettext("User actions")}</summary>
        <div class="mt-2 p-3 rounded-box border border-base-300 bg-base-100 space-y-3">
          <details :if={@actions.bannable? and not @actions.banned?} id="user-actions-ban">
            <summary class="link">{gettext("Ban…")}</summary>
            <.form
              for={%{}}
              action={~p"/u/#{@user.id}/ban"}
              method="post"
              id="ban-form"
              class="mt-2 space-y-2"
            >
              <input
                :if={@actions.return_to}
                type="hidden"
                name="return_to"
                value={@actions.return_to}
              />
              <label class="block">
                <span class="label mb-1">{gettext("For")}</span>
                <select name="days" class="select select-sm w-full" id="ban-days">
                  <option value="1">{gettext("1 day")}</option>
                  <option value="7">{gettext("7 days")}</option>
                  <option value="30">{gettext("30 days")}</option>
                  <option value="365">{gettext("1 year")}</option>
                  <option value="forever">{gettext("For good")}</option>
                </select>
              </label>
              <label class="block">
                <span class="label mb-1">{gettext("Reason (shown in the moderation log)")}</span>
                <input type="text" name="reason" maxlength="500" class="input input-sm w-full" />
              </label>
              <button
                class="btn btn-sm btn-error"
                data-confirm={gettext("Ban this account? It is signed out at once.")}
              >
                {gettext("Ban account")}
              </button>
            </.form>
          </details>
          <.form
            :if={@user.banned_at}
            for={%{}}
            action={~p"/u/#{@user.id}/ban"}
            method="delete"
            id="unban-form"
            class="space-y-2"
          >
            <input :if={@actions.return_to} type="hidden" name="return_to" value={@actions.return_to} />
            <label class="block">
              <span class="label mb-1">{gettext("Reason (shown in the moderation log)")}</span>
              <input type="text" name="reason" maxlength="500" class="input input-sm w-full" />
            </label>
            <button class="btn btn-sm">{gettext("Lift ban")}</button>
          </.form>
          <p
            :if={!@actions.bannable? and !@user.banned_at}
            class="text-sm opacity-70"
            id="not-bannable"
          >
            {gettext("Owners and administrators cannot be banned.")}
          </p>
        </div>
      </details>
    </div>
    """
  end

  @doc """
  A user's avatar (AC-04): their picture, or their initial on a plain circle. Decorative:
  the name is always shown next to it, so it has no text of its own for screen readers.
  """
  attr :user, :map, required: true
  attr :size, :atom, values: [:small, :list, :medium, :large], default: :small

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
  defp box(:list), do: "w-9 text-sm"
  defp box(:medium), do: "w-12 text-lg"
  defp box(:large), do: "w-14 text-xl"

  defp initial(user), do: user.display_name |> String.first() |> String.upcase()
end

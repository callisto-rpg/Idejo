# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.InvitesLive do
  @moduledoc """
  Admin panel: invites (AC-02). An administrator creates a single-use invite link, valid for
  7 days, and passes it on; the list shows which are unused, used or expired.
  """
  use IdejoWeb, :live_view

  alias Idejo.Accounts
  alias Idejo.Accounts.Invite
  alias Idejo.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Invites"))
     |> assign(:invite_only?, Settings.get(:registration_mode) == "invite_only")
     |> assign(:new_invite, nil)
     |> load_invites()}
  end

  defp load_invites(socket) do
    assign(socket, invites: Accounts.list_invites(), now: DateTime.utc_now())
  end

  @impl true
  def handle_event("create", _params, socket) do
    {:ok, invite} = Accounts.create_invite(socket.assigns.current_scope.user)

    {:noreply,
     socket
     |> assign(:new_invite, invite)
     |> load_invites()}
  end

  defp invite_url(invite), do: url(~p"/users/sign-up?invite=#{invite.code}")

  defp status_text(invite, now) do
    case Invite.status(invite, now) do
      :unused -> gettext("Unused")
      :used -> gettext("Used by %{name}", name: invite.user.display_name)
      :expired -> gettext("Expired")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:invites}>
      <.header>
        {gettext("Invites")}
        <:subtitle>
          {gettext("Each link lets one person sign up, for %{days} days.",
            days: Invite.validity_in_days()
          )}
        </:subtitle>
      </.header>

      <p :if={!@invite_only?} class="alert alert-info">
        {gettext(
          "Anyone can sign up right now, so invites are not needed. Switch to invite-only in Settings."
        )}
      </p>

      <button id="create-invite" type="button" class="btn btn-primary" phx-click="create">
        {gettext("Create an invite link")}
      </button>

      <div :if={@new_invite} id="new-invite" class="mt-4 space-y-1">
        <label for="new-invite-url" class="font-semibold">
          {gettext("New invite link — copy it and send it to one person:")}
        </label>
        <input
          id="new-invite-url"
          type="text"
          readonly
          value={invite_url(@new_invite)}
          class="input w-full font-mono"
        />
      </div>

      <.table :if={@invites != []} id="invites" rows={@invites} row_id={&"invite-#{&1.code}"}>
        <:col :let={invite} label={gettext("Link")}>
          <code :if={Invite.status(invite, @now) == :unused} class="text-xs break-all">
            {invite_url(invite)}
          </code>
          <span :if={Invite.status(invite, @now) != :unused} class="opacity-70">—</span>
        </:col>
        <:col :let={invite} label={gettext("Status")}>{status_text(invite, @now)}</:col>
        <:col :let={invite} label={gettext("Expires")}>
          <time datetime={DateTime.to_iso8601(invite.expires_at)}>
            {Calendar.strftime(invite.expires_at, "%Y-%m-%d %H:%M UTC")}
          </time>
        </:col>
        <:col :let={invite} label={gettext("Created by")}>{invite.creator.display_name}</:col>
      </.table>
    </Layouts.admin>
    """
  end
end

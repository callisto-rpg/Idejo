# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.IdejoIdLive do
  @moduledoc """
  Admin → idejo ID (AC-09; steward decisions, 2026-11-06): connect the server to an idejo ID
  registry (`Idejo.Accounts.OIDCRegistry`), so members sign in with their idejo ID, and ask
  to be listed in its directory of forums, which only a connected server may (the registry's
  operator approves). Set by the environment (`IDEJO_OIDC_*`), the page only says so.
  Extra review: DV-06.
  """
  use IdejoWeb, :live_view

  alias Idejo.Accounts.{OIDC, OIDCRegistry}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: gettext("idejo ID"), busy?: false) |> load()}
  end

  defp load(socket) do
    environment? = Application.get_env(:idejo, :oidc) != nil

    listing =
      case !environment? && OIDCRegistry.listing() do
        {:ok, status} -> status
        _ -> nil
      end

    assign(socket,
      environment?: environment?,
      connection: OIDCRegistry.config(),
      registry: OIDCRegistry.registry_url(),
      label: OIDC.label(),
      listing: listing
    )
  end

  @impl true
  def handle_event("connect", _params, socket) do
    socket =
      case OIDCRegistry.connect(socket.assigns.current_scope.user) do
        {:ok, label} ->
          put_flash(
            socket,
            :info,
            gettext("Connected: members can now sign in with %{label}.", label: label)
          )

        {:error, reason} ->
          put_flash(socket, :error, error_text(reason))
      end

    {:noreply, load(socket)}
  end

  def handle_event("disconnect", _params, socket) do
    :ok = OIDCRegistry.disconnect(socket.assigns.current_scope.user)
    {:noreply, socket |> put_flash(:info, gettext("Disconnected from idejo ID.")) |> load()}
  end

  def handle_event("listing", params, socket) do
    listed? = params["listed"] == "true"

    socket =
      case OIDCRegistry.set_listed(socket.assigns.current_scope.user, listed?) do
        {:ok, _status} -> socket
        {:error, reason} -> put_flash(socket, :error, error_text(reason))
      end

    {:noreply, load(socket)}
  end

  defp error_text(message) when is_binary(message),
    do: gettext("idejo ID answered: %{message}", message: message)

  defp error_text(:unreachable),
    do: gettext("idejo ID could not be reached: try again in a moment.")

  defp error_text(:environment),
    do: gettext("This server's environment already sets a sign-in provider.")

  defp error_text(:not_connected), do: gettext("Connect to idejo ID first.")

  defp error_text(_reason),
    do: gettext("idejo ID gave an answer this server does not understand.")

  defp registry_host(nil), do: nil
  defp registry_host(url), do: URI.parse(url).host

  defp directory_host(%{} = connection) do
    case connection[:directory_url] do
      "http" <> _ = url -> URI.parse(url).host
      _ -> nil
    end
  end

  defp directory_host(_), do: nil

  defp listing_text("requested"), do: gettext("Waiting for the directory's approval.")
  defp listing_text("approved"), do: gettext("Listed in the directory.")

  defp listing_text("refused"),
    do: gettext("The directory's operator did not approve the listing.")

  defp listing_text(_none), do: gettext("Not listed.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:idejo_id}>
      <h1 class="page-intro">{gettext("idejo ID")}</h1>

      <section :if={@environment?} id="idejo-id-environment" class="space-y-2">
        <p>
          {gettext(
            "Members sign in with %{label}, set by this server's environment (IDEJO_OIDC_*). Change it there.",
            label: @label
          )}
        </p>
      </section>

      <section :if={!@environment? and is_nil(@connection)} id="idejo-id-connect" class="space-y-3">
        <p>
          {gettext(
            "Let members sign in with their idejo ID: one account for every idejo forum that uses it. Local accounts keep working."
          )}
        </p>
        <p :if={is_nil(@registry)}>
          {gettext("Connecting to idejo ID is turned off on this server (IDEJO_ID_REGISTRY_URL).")}
        </p>
        <button
          :if={@registry}
          id="idejo-id-connect-button"
          class="btn btn-primary"
          phx-click="connect"
          phx-disable-with={gettext("Connecting…")}
        >
          {gettext("Connect to idejo ID (%{host})", host: registry_host(@registry))}
        </button>
        <p :if={@registry} class="text-sm">
          {gettext(
            "%{host} checks that this server answers at its own address, then gives it its sign-in credentials.",
            host: registry_host(@registry)
          )}
        </p>
      </section>

      <section :if={!@environment? and @connection} id="idejo-id-connected" class="space-y-3">
        <p>
          {gettext("Connected to %{issuer}: members sign in with %{label}.",
            issuer: @connection[:issuer],
            label: @connection[:label]
          )}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            id="idejo-id-renew"
            class="btn btn-sm"
            phx-click="connect"
            phx-disable-with={gettext("Connecting…")}
          >
            {gettext("Renew the connection")}
          </button>
          <button
            id="idejo-id-disconnect"
            class="btn btn-sm btn-error"
            phx-click="disconnect"
            data-confirm={
              gettext(
                "Disconnect from idejo ID? Members can no longer sign in with it here until you connect again."
              )
            }
          >
            {gettext("Disconnect")}
          </button>
        </div>
      </section>

      <section :if={!@environment?} id="idejo-id-directory" class="space-y-3 mt-8">
        <h2 class="text-lg font-semibold">{gettext("Forums directory")}</h2>
        <p :if={is_nil(@connection)}>
          {gettext("Only forums that sign in with idejo ID can be listed. Connect to idejo ID first.")}
        </p>
        <form :if={@connection} id="idejo-id-listing" phx-change="listing">
          <input type="hidden" name="listed" value="false" />
          <label class="flex items-center gap-2">
            <input
              type="checkbox"
              name="listed"
              value="true"
              class="checkbox"
              checked={@listing in ["requested", "approved"]}
            />
            {gettext("List this forum on the forums directory (%{host})",
              host: directory_host(@connection) || registry_host(@connection[:registry_url])
            )}
          </label>
        </form>
        <p :if={@connection} id="idejo-id-listing-status" role="status">{listing_text(@listing)}</p>
      </section>
    </Layouts.admin>
    """
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AppAuthorizeController do
  @moduledoc """
  The official app's sign-in page (AP-08; steward decision, 2026-11-10), opened by the app
  in a Custom Tab with the forum's normal session, so passwords, Idejo ID and whatever
  sign-in the forum has all work unchanged.

  `GET /app/authorize` checks the request first (`ApiTokens.check_request/1`): a wrong
  client id or redirect, no S256 challenge or a malformed one shows a plain error page and
  **never** redirects. Not signed in, it goes through the normal sign-in, which comes back
  here (`:user_return_to`). Signed in, it asks "Sign in to the Idejo app on this device as
  {name}?" with what the app may do; Allow (a POST with the CSRF token) redirects to
  `org.idejo.app:/oauth/callback?code=…&state=…`, Cancel with `error=access_denied`.

  Changes to this module get an extra careful human review (DV-06).
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts
  alias Idejo.Accounts.ApiTokens

  @fields ~w(response_type client_id redirect_uri scope state code_challenge code_challenge_method device_name)

  def new(conn, params) do
    case {ApiTokens.check_request(params), conn.assigns.current_scope} do
      {{:error, reason}, _scope} ->
        refuse(conn, reason)

      {{:ok, request}, %{user: %Accounts.User{} = user}} ->
        render_confirmation(conn, user, request, params)

      {{:ok, _request}, _visitor} ->
        conn
        |> put_session(:user_return_to, current_path(conn))
        |> put_flash(:info, gettext("Sign in to connect the Idejo app."))
        |> redirect(to: ~p"/users/sign-in")
    end
  end

  def create(conn, params) do
    with {:ok, request} <- ApiTokens.check_request(params),
         %{user: %Accounts.User{} = user} <- conn.assigns.current_scope || {:error, :signed_out} do
      decide(conn, user, request, params["choice"])
    else
      {:error, :signed_out} -> redirect(conn, to: ~p"/users/sign-in")
      {:error, reason} -> refuse(conn, reason)
    end
  end

  defp decide(conn, user, request, "allow") do
    case ApiTokens.create_code(user, request) do
      {:ok, code} -> callback(conn, %{"code" => code}, request)
      {:error, reason} -> refuse(conn, reason)
    end
  end

  defp decide(conn, _user, request, _cancel),
    do: callback(conn, %{"error" => "access_denied"}, request)

  # The fixed redirect only (AP-08), with the app's own state.
  defp callback(conn, query, request) do
    query = if request.state, do: Map.put(query, "state", request.state), else: query

    conn
    |> put_resp_header("cache-control", "no-store")
    |> redirect(external: ApiTokens.redirect_uri() <> "?" <> URI.encode_query(query))
  end

  defp render_confirmation(conn, user, request, params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> render(:new,
      page_title: gettext("Sign in to the Idejo app"),
      user: user,
      request: request,
      hidden: Map.take(params, @fields)
    )
  end

  defp refuse(conn, reason) do
    conn
    |> put_status(if(reason in [:banned, :inactive], do: 403, else: 400))
    |> render(:error, page_title: gettext("Sign in to the Idejo app"), reason: reason)
  end
end

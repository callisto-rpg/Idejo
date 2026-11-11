# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.ApiAuth do
  @moduledoc """
  Who calls the API (AP-09, AP-10, AP-18, AP-20; steward decision, 2026-11-10). The only
  credential is `Authorization: Bearer idj_…`, the official app's device token; no session,
  no cookie is read or written.

  Each route's operation (`IdejoWeb.Api.Operations`) says which scope it needs:

    * none: anyone; a valid token is still read (the app's sign-out names it so);
    * otherwise: no token is `401 unauthenticated`, an unknown or revoked one `401
      invalid_token`, a banned account `403 banned` (for good) or `403 suspended` (until a
      date), a token without the scope `403 insufficient_scope`.

  The user comes from `Idejo.Accounts.get_user_by_api_token/1`, the same rules as a browser
  session's. Assigns `:current_user` and `:api_token`. Every request with a valid token
  counts towards its overall limit (`:api_token`); others count towards the address's
  (`:request`).

  Changes to this module get an extra careful human review (DV-06).
  """
  @behaviour Plug

  import Plug.Conn

  alias Idejo.Accounts
  alias Idejo.RateLimit
  alias IdejoWeb.Api.{Errors, Operations}
  alias IdejoWeb.Plugs.RateLimit, as: AddressLimit

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = conn |> assign(:current_user, nil) |> assign(:api_token, nil)

    case operation(conn) do
      nil -> conn
      %{scope: nil} -> optional(conn)
      %{scope: scope} -> required(conn, scope)
    end
  end

  # The route's operation, looked up from the request itself: the router has not put the
  # controller in `conn.private` yet while its pipelines run.
  defp operation(conn) do
    case Phoenix.Router.route_info(IdejoWeb.Router, conn.method, conn.request_path, conn.host) do
      %{plug: controller, plug_opts: action} -> Operations.find(controller, action)
      :error -> nil
    end
  end

  defp optional(conn) do
    case bearer(conn) do
      nil ->
        AddressLimit.count(conn, :request)

      token ->
        case Accounts.get_user_by_api_token(token) do
          {:ok, user, row} -> conn |> signed_in(user, row) |> limit()
          _error -> AddressLimit.count(conn, :request)
        end
    end
  end

  defp required(conn, scope) do
    with token when is_binary(token) <- bearer(conn) || {:error, :unauthenticated},
         {:ok, user, row} <- Accounts.get_user_by_api_token(token) do
      conn |> signed_in(user, row) |> limit() |> scope(scope, row)
    else
      {:error, reason} -> refuse(conn, reason)
    end
  end

  defp scope(%{halted: true} = conn, _scope, _row), do: conn

  defp scope(conn, scope, row),
    do: if(scope in row.scopes, do: conn, else: refuse(conn, :insufficient_scope))

  defp signed_in(conn, user, row),
    do: conn |> assign(:current_user, user) |> assign(:api_token, row)

  defp refuse(conn, :disabled), do: Errors.send_error(conn, :not_found)

  defp refuse(conn, reason) when reason in [:unauthenticated, :invalid] do
    conn = AddressLimit.count(conn, :request)

    if conn.halted,
      do: conn,
      else: Errors.send_error(conn, if(reason == :invalid, do: :invalid_token, else: reason))
  end

  defp refuse(conn, reason), do: Errors.send_error(conn, reason)

  defp limit(%{assigns: %{api_token: row}} = conn) do
    case RateLimit.check(:api_token, row.id) do
      :ok -> conn
      {:error, :rate_limited} -> Errors.send_error(conn, :rate_limited, %{"retry_after" => 60})
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      _ -> nil
    end
  end
end

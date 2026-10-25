# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PushSubscriptionController do
  @moduledoc """
  The browser's push subscription (PN-13, PN-16), saved or removed by `assets/js/push.js`
  with `fetch`: JSON as `PushSubscription.toJSON()` gives it, the CSRF token in
  `x-csrf-token`. Signed-in users only; the subscription belongs to this sign-in session, so
  it ends with it. Answers 204, or 422 with `{"error": reason}` (429 when rate-limited, 404
  when push is off).

  Changes to this module get an extra careful human review (DV-06).
  """
  use IdejoWeb, :controller

  alias Idejo.Accounts
  alias Idejo.Push

  def create(conn, params) do
    user = conn.assigns.current_scope.user
    session_id = conn |> get_session(:user_token) |> then(&(&1 && Accounts.session_socket_id(&1)))
    user_agent = conn |> get_req_header("user-agent") |> List.first()

    case Push.subscribe(user, session_id, params, user_agent) do
      {:ok, _subscription} -> send_resp(conn, 204, "")
      {:error, :disabled} -> error(conn, 404, :disabled)
      {:error, :rate_limited} -> error(conn, 429, :rate_limited)
      {:error, %Ecto.Changeset{}} -> error(conn, 422, :invalid)
      {:error, reason} -> error(conn, 422, reason)
    end
  end

  def delete(conn, %{"endpoint" => endpoint}) when is_binary(endpoint) do
    :ok = Push.unsubscribe(conn.assigns.current_scope.user, endpoint)
    send_resp(conn, 204, "")
  end

  def delete(conn, _params), do: error(conn, 422, :invalid)

  defp error(conn, status, reason), do: conn |> put_status(status) |> json(%{error: reason})
end

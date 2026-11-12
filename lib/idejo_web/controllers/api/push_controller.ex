# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.PushController do
  @moduledoc """
  UnifiedPush for the official app (AP-19; steward decision, 2026-11-10): the app registers
  its distributor's endpoint with Web Push keys, and gets the same pushes as a browser
  (PN-01 to PN-16), encrypted (RFC 8291) and signed (VAPID) by `Idejo.Push`.

  Changes to this module get an extra careful human review (DV-06).
  """
  use IdejoWeb.Api.Controller

  alias Idejo.Push

  def index(conn, _params) do
    send_list(conn, Enum.map(Push.list_subscriptions(user(conn)), &registration(conn, &1)))
  end

  def register(conn, params) do
    case Push.register_unifiedpush(user(conn), conn.assigns.api_token.id, params) do
      {:ok, subscription} -> json(conn, registration(conn, subscription))
      {:error, :disabled} -> {:error, :push_disabled}
      {:error, :invalid} -> {:error, :validation, %{"fields" => %{"endpoint" => ["is invalid"]}}}
      error -> error
    end
  end

  def delete(conn, %{"id" => id}) do
    case Push.remove_subscription(user(conn), id) do
      {:ok, _endpoint} -> no_content(conn)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def test(conn, _params) do
    case Push.send_test(user(conn)) do
      {:ok, count} -> json(conn, %{"queued" => count})
      {:error, :disabled} -> {:error, :push_disabled}
      error -> error
    end
  end

  defp registration(conn, subscription) do
    %{
      "id" => subscription.id,
      "kind" => subscription.kind,
      "name" => subscription.name || subscription.user_agent,
      "endpoint_host" => URI.parse(subscription.endpoint).host,
      "this_device" => subscription.api_token_id == conn.assigns.api_token.id,
      "created_at" => Api.time(subscription.created_at),
      "last_success_at" => Api.time(subscription.last_success_at)
    }
  end
end

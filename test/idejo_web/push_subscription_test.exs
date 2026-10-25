# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PushSubscriptionTest do
  # Not async: one test turns push off, a server-wide setting.
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Push
  alias Idejo.Settings

  defp browser(endpoint \\ "https://updates.push.services.mozilla.com/wpush/v2/abc") do
    {public, _private} = :crypto.generate_key(:ecdh, :prime256v1)

    %{
      "endpoint" => endpoint,
      "keys" => %{
        "p256dh" => Base.url_encode64(public, padding: false),
        "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      }
    }
  end

  setup %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    token = Plug.Conn.get_session(conn, :user_token)
    %{conn: conn, user: user, socket_id: Accounts.session_socket_id(token)}
  end

  @tag req: "PN-13"
  test "PN-13 a signed-in browser saves and removes its subscription", %{
    conn: conn,
    user: user,
    socket_id: socket_id
  } do
    sent = browser()

    conn =
      conn
      |> put_req_header("user-agent", "Mozilla/5.0 (Android 16) Chrome/141")
      |> post(~p"/push/subscriptions", sent)

    assert response(conn, 204)
    assert [saved] = Push.list_subscriptions(user)
    assert saved.endpoint == sent["endpoint"]
    assert saved.session_id == socket_id
    assert saved.user_agent == "Mozilla/5.0 (Android 16) Chrome/141"

    conn = delete(recycle(conn), ~p"/push/subscriptions", %{"endpoint" => sent["endpoint"]})
    assert response(conn, 204)
    assert Push.list_subscriptions(user) == []
  end

  @tag req: "PN-13"
  test "PN-13 visitors cannot subscribe" do
    conn = post(build_conn(), ~p"/push/subscriptions", browser())
    assert redirected_to(conn) == ~p"/users/sign-in"
  end

  @tag req: "PN-16"
  test "PN-16 an endpoint the server may not reach is refused with its reason", %{
    conn: conn,
    user: user
  } do
    conn = post(conn, ~p"/push/subscriptions", browser("https://metadata.push.apple.com/x"))
    assert json_response(conn, 422) == %{"error" => "private_address"}

    conn =
      post(recycle(conn), ~p"/push/subscriptions", %{"endpoint" => "https://fcm.googleapis.com/x"})

    assert json_response(conn, 422) == %{"error" => "invalid"}

    assert Push.list_subscriptions(user) == []
  end

  @tag req: "PN-19"
  test "PN-19 subscribing answers 404 while push is off", %{conn: conn} do
    {:ok, _} =
      Settings.update_settings(user_with_role_fixture(:administrator), %{"push_enabled" => "off"})

    assert json_response(post(conn, ~p"/push/subscriptions", browser()), 404) == %{
             "error" => "disabled"
           }
  end
end

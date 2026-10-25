# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ServiceWorkerTest do
  # Not async: one test turns push off, a server-wide setting.
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Push
  alias Idejo.Push.Vapid
  alias Idejo.Settings

  defp keys do
    {public, _private} = :crypto.generate_key(:ecdh, :prime256v1)

    %{
      "p256dh" => Base.url_encode64(public, padding: false),
      "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }
  end

  defp push_key(conn) do
    conn
    |> get(~p"/")
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("meta[name='push-key']")
    |> LazyHTML.attribute("content")
  end

  describe "the service worker (PN-17)" do
    @tag req: "PN-17"
    test "PN-17 is served from the root, for the whole site, with no session", %{conn: conn} do
      conn = get(conn, ~p"/sw.js")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["text/javascript; charset=utf-8"]
      assert get_resp_header(conn, "service-worker-allowed") == ["/"]
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
      assert get_resp_header(conn, "set-cookie") == []
    end

    @tag req: "PN-17"
    test "PN-17 handles push, clicks and renewed subscriptions, importing nothing", %{conn: conn} do
      worker = conn |> get(~p"/sw.js") |> response(200)

      for event <- ~w(push notificationclick pushsubscriptionchange) do
        assert worker =~ ~s{addEventListener("#{event}"}
      end

      assert worker =~ "showNotification"
      assert worker =~ "renotify"
      assert worker =~ "openWindow"
      refute worker =~ "importScripts"
      refute worker =~ ~r/^\s*import\b/m
      refute worker =~ ~r{https?://}
    end

    @tag req: "PN-17"
    test "PN-17 gives the public key it subscribes with", %{conn: conn} do
      conn = get(conn, ~p"/push/key")
      assert response(conn, 200) == Vapid.public_key()
      assert get_resp_header(conn, "set-cookie") == []
    end

    @tag req: "PN-17"
    test "PN-17 saves a subscription the push service replaced, for the same user and session" do
      user = user_fixture()
      old = "https://fcm.googleapis.com/fcm/send/old"
      {:ok, saved} = Push.subscribe(user, "the-session", %{"endpoint" => old, "keys" => keys()})
      new = %{"endpoint" => "https://fcm.googleapis.com/fcm/send/new", "keys" => keys()}

      # The worker sends no cookie and no CSRF token.
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/push/subscriptions/renew",
          Jason.encode!(%{old_endpoint: old, subscription: new})
        )

      assert response(conn, 204)
      assert [renewed] = Push.list_subscriptions(user)
      assert renewed.id == saved.id
      assert renewed.endpoint == new["endpoint"]
      assert renewed.p256dh == new["keys"]["p256dh"]
      assert renewed.session_id == "the-session"
    end

    @tag req: "PN-16"
    test "PN-16 a renewal needs a saved endpoint and a new one the server may reach", %{
      conn: conn
    } do
      user = user_fixture()
      old = "https://fcm.googleapis.com/fcm/send/#{System.unique_integer([:positive])}"
      {:ok, _} = Push.subscribe(user, "s", %{"endpoint" => old, "keys" => keys()})

      unknown = %{
        old_endpoint: "https://fcm.googleapis.com/fcm/send/nobody",
        subscription: %{"endpoint" => "https://fcm.googleapis.com/x", "keys" => keys()}
      }

      assert json_response(post(conn, ~p"/push/subscriptions/renew", unknown), 404) == %{
               "error" => "not_found"
             }

      inside = %{
        old_endpoint: old,
        subscription: %{"endpoint" => "https://metadata.push.apple.com/x", "keys" => keys()}
      }

      assert json_response(post(build_conn(), ~p"/push/subscriptions/renew", inside), 422) ==
               %{"error" => "private_address"}

      assert [%{endpoint: ^old}] = Push.list_subscriptions(user)
    end
  end

  describe "the key in pages (PN-18)" do
    @tag req: "PN-18"
    test "PN-18 signed-in pages carry the push key, so the browser keeps its subscription", %{
      conn: conn
    } do
      assert push_key(conn) == []
      assert push_key(log_in_user(build_conn(), user_fixture())) == [Vapid.public_key()]

      script = File.read!("assets/js/push.js")
      assert File.read!("assets/js/app.js") =~ ~s(import "./push")
      assert script =~ ~s(Notification.permission !== "granted")
      assert script =~ "window.pushManager ||"
      assert script =~ "getSubscription()"
      assert script =~ "requestPermission()"
    end

    @tag req: "PN-19"
    test "PN-19 no page carries the key while push is off" do
      {:ok, _} =
        Settings.update_settings(user_with_role_fixture(:administrator), %{
          "push_enabled" => "off"
        })

      assert push_key(log_in_user(build_conn(), user_fixture())) == []

      assert json_response(
               post(build_conn(), ~p"/push/subscriptions/renew", %{
                 old_endpoint: "x",
                 subscription: %{}
               }),
               404
             )
    end
  end
end

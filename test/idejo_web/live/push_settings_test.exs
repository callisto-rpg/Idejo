# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PushSettingsTest do
  # Not async: a test turns push off server-wide.
  use IdejoWeb.ConnCase, async: false
  use Oban.Testing, repo: Idejo.Repo

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Push
  alias Idejo.Push.Worker
  alias Idejo.Settings
  alias IdejoWeb.UserSettingsLive

  @firefox "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
  @iphone "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

  defp browser(user, user_agent) do
    {public, _private} = :crypto.generate_key(:ecdh, :prime256v1)

    {:ok, subscription} =
      Push.subscribe(
        user,
        "session",
        %{
          "endpoint" =>
            "https://fcm.googleapis.com/fcm/send/#{System.unique_integer([:positive])}",
          "keys" => %{
            "p256dh" => Base.url_encode64(public, padding: false),
            "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
          }
        },
        user_agent
      )

    subscription
  end

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @tag req: "PN-24"
  test "PN-24 the browser's state, the switches, the devices and a test notification", %{
    conn: conn,
    user: user
  } do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    assert has_element?(lv, "#push-notifications-heading", "Push notifications")

    # This browser's state: worked out by the hook, each line in the markup.
    assert has_element?(lv, "#push-browser[phx-hook=PushSettings][role=status]")
    assert has_element?(lv, "#push-browser .push-browser-turn-on", "Turn on")
    assert has_element?(lv, "#push-browser .push-browser-blocked[hidden]", "blocked")
    assert has_element?(lv, "#push-browser .push-browser-ios[hidden]", "Home Screen")

    # No device yet: the test says so.
    assert has_element?(lv, "#push-no-devices")
    lv |> element("#push-test") |> render_click()
    assert render(lv) =~ "No device takes notifications yet. Turn them on first."

    laptop = browser(user, @firefox)
    phone = browser(user, @iphone)

    # Turned on in the hook: the list reloads, and this browser is marked.
    render_hook(lv, "push_changed", %{})
    render_hook(lv, "push_endpoint", %{"endpoint" => laptop.endpoint})
    assert has_element?(lv, "#push-device-#{laptop.id}", "Firefox on Linux")
    assert has_element?(lv, "#push-device-#{laptop.id} .badge", "This browser")
    assert has_element?(lv, "#push-device-#{phone.id}", "Safari on iPhone")
    refute has_element?(lv, "#push-device-#{phone.id} .badge")

    # Send test notification: one push per device.
    lv |> element("#push-test") |> render_click()
    assert render(lv) =~ "Test notification sent."
    assert length(all_enqueued(worker: Worker)) == 2

    assert hd(all_enqueued(worker: Worker)).args["payload"]["notification"]["title"] ==
             "Test notification"

    # Remove the phone: gone. Remove this browser: the page ends its subscription too.
    lv |> element(~s(#push-device-#{phone.id} button), "Remove") |> render_click()
    refute has_element?(lv, "#push-device-#{phone.id}")
    refute_push_event(lv, "push_unsubscribe", %{})

    lv |> element(~s(#push-device-#{laptop.id} button), "Remove") |> render_click()
    assert_push_event(lv, "push_unsubscribe", %{})
    assert Push.list_subscriptions(user) == []

    # Someone else's device cannot be removed.
    other = browser(user_fixture(), @firefox)
    assert Push.remove_subscription(user, other.id) == {:error, :not_found}

    js = File.read!("assets/js/push.js")
    assert js =~ ~s|const OFF_HERE = "idejo:push-off"|
    assert js =~ "Notification.permission !== \"granted\" || offHere()) return"
  end

  @tag req: "PN-11"
  test "PN-11 the four switches are saved for all the user's devices", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    lv
    |> form("#push-notifications-form",
      push: %{reply: "true", mention: "true", role_mention: "false", followed: "false"}
    )
    |> render_submit()

    assert render(lv) =~ "Push notifications saved."
    preference = Push.preferences(user)
    assert {preference.reply, preference.mention} == {true, true}
    assert {preference.role_mention, preference.followed} == {false, false}
  end

  @tag req: "PN-19"
  test "PN-19 no push section while push is off", %{conn: conn} do
    {:ok, _} =
      Settings.update_settings(user_with_role_fixture(:administrator), %{"push_enabled" => "off"})

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    refute has_element?(lv, "#push-notifications-heading")
  end

  test "devices are named from their browser" do
    assert UserSettingsLive.device_name(@firefox) == "Firefox on Linux"
    assert UserSettingsLive.device_name(@iphone) == "Safari on iPhone"

    assert UserSettingsLive.device_name(
             "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36 Edg/140.0"
           ) == "Edge on Windows"

    assert UserSettingsLive.device_name(nil) == "Unknown browser"
  end
end

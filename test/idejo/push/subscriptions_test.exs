# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.SubscriptionsTest do
  # Not async: some tests change server-wide settings (the switch, the allowlist).
  use Idejo.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureIO
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Audit
  alias Idejo.Push
  alias Idejo.Push.Subscription
  alias Idejo.Release
  alias Idejo.Settings

  defp browser(
         endpoint \\ "https://fcm.googleapis.com/fcm/send/#{System.unique_integer([:positive])}"
       ) do
    {public, _private} = :crypto.generate_key(:ecdh, :prime256v1)

    %{
      "endpoint" => endpoint,
      "expirationTime" => nil,
      "keys" => %{
        "p256dh" => Base.url_encode64(public, padding: false),
        "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16))
      }
    }
  end

  defp session(user) do
    token = Accounts.generate_user_session_token(user)
    {token, Accounts.session_socket_id(token)}
  end

  defp count(user), do: length(Push.list_subscriptions(user))

  describe "subscribe" do
    @tag req: "PN-13"
    test "PN-13 saves a browser's subscription for the user and their session" do
      user = user_fixture()
      {_token, socket_id} = session(user)
      sent = browser()

      assert {:ok, saved} = Push.subscribe(user, socket_id, sent, "Mozilla/5.0 (X11) Firefox/140")

      assert saved.user_id == user.id
      assert saved.endpoint == sent["endpoint"]
      assert saved.p256dh == sent["keys"]["p256dh"]
      # Stored without Base64 padding, whatever the browser sent.
      assert saved.auth == String.trim_trailing(sent["keys"]["auth"], "=")
      assert saved.session_id == socket_id
      assert saved.user_agent == "Mozilla/5.0 (X11) Firefox/140"
      assert saved.failure_count == 0
      assert {<<4, _::binary-size(64)>>, <<_::binary-size(16)>>} = Subscription.keys(saved)
    end

    @tag req: "PN-13"
    test "PN-13 the same endpoint saved again keeps one row, now for whoever saved it" do
      ada = user_fixture()
      bea = user_fixture()
      sent = browser()

      {:ok, first} = Push.subscribe(ada, "one", sent)
      Repo.update_all(Subscription, set: [failure_count: 3])
      {:ok, again} = Push.subscribe(bea, "two", sent)

      assert again.id == first.id
      assert again.user_id == bea.id
      assert again.session_id == "two"
      assert again.failure_count == 0
      assert count(ada) == 0
      assert count(bea) == 1
    end

    @tag req: "PN-13"
    test "PN-13 an eleventh browser removes the user's oldest" do
      user = user_fixture()

      saved =
        for n <- 1..10 do
          {:ok, subscription} = Push.subscribe(user, "session", browser())
          at = DateTime.add(~U[2026-10-01 00:00:00.000000Z], n, :minute)

          Repo.update_all(from(s in Subscription, where: s.id == ^subscription.id),
            set: [created_at: at]
          )

          subscription
        end

      {:ok, eleventh} = Push.subscribe(user, "session", browser())

      left = Push.list_subscriptions(user) |> Enum.map(& &1.id)
      assert length(left) == Push.max_per_user()
      refute hd(saved).id in left
      assert eleventh.id in left
      assert Enum.at(saved, 1).id in left
    end

    @tag req: "PN-13"
    test "PN-13 keys that are not a P-256 point and a 16-byte secret are refused" do
      user = user_fixture()
      good = browser()

      for keys <- [
            %{good["keys"] | "p256dh" => Base.url_encode64(<<4>> <> :binary.copy(<<1>>, 64))},
            %{good["keys"] | "p256dh" => "not base64!"},
            %{good["keys"] | "auth" => Base.url_encode64(:crypto.strong_rand_bytes(8))},
            %{}
          ] do
        assert {:error, %Ecto.Changeset{}} = Push.subscribe(user, "s", %{good | "keys" => keys})
      end

      assert count(user) == 0
    end

    @tag req: "PN-19"
    test "PN-19 nobody subscribes while push is off" do
      admin = user_with_role_fixture(:administrator)
      {:ok, _} = Settings.update_settings(admin, %{"push_enabled" => "off"})

      assert Push.subscribe(admin, "s", browser()) == {:error, :disabled}
      assert count(admin) == 0
    end

    @tag req: "PN-16"
    test "PN-16 subscribing is rate-limited per user" do
      Application.put_env(:idejo, :rate_limits, enabled: true)
      on_exit(fn -> Application.put_env(:idejo, :rate_limits, enabled: false) end)
      user = user_fixture()
      {limit, _window} = Idejo.RateLimit.limit(:push_subscribe)

      for _ <- 1..limit, do: assert({:ok, _} = Push.subscribe(user, "s", browser()))
      assert Push.subscribe(user, "s", browser()) == {:error, :rate_limited}
    end
  end

  describe "endpoint checks (PN-16)" do
    @tag req: "PN-16"
    test "PN-16 only https endpoints of allowed push services with public addresses are saved" do
      user = user_fixture()

      for {endpoint, reason} <- [
            {"http://fcm.googleapis.com/fcm/send/x", :not_https},
            {"ftp://fcm.googleapis.com/x", :not_https},
            {"https://user:pass@fcm.googleapis.com/x", :invalid},
            {"https:///nohost", :invalid},
            {"not a url", :invalid},
            {"https://evil.example.org/push", :not_allowed},
            {"https://googleapis.com.evil.example.org/x", :not_allowed},
            {"https://push.apple.com/x", :not_allowed},
            {"https://10.0.0.5/x", :not_allowed},
            {"https://[::1]/x", :not_allowed},
            {"https://nxdomain.push.apple.com/x", :unresolvable},
            {"https://loopback.push.apple.com/x", :private_address},
            {"https://ipv6-loopback.push.apple.com/x", :private_address},
            {"https://metadata.push.apple.com/latest/meta-data", :private_address},
            {"https://mapped.push.apple.com/x", :private_address},
            {"https://ula.push.apple.com/x", :private_address},
            {"https://rebind.push.apple.com/x", :private_address}
          ] do
        assert Push.subscribe(user, "s", browser(endpoint)) == {:error, reason}, endpoint
      end

      for endpoint <- [
            "https://fcm.googleapis.com/fcm/send/abc",
            "https://updates.push.services.mozilla.com/wpush/v2/abc",
            "https://web.push.apple.com/QGd2",
            "https://WNS2-PAR02P.notify.windows.com/w/?token=abc"
          ] do
        assert {:ok, _} = Push.subscribe(user, "s", browser(endpoint)), endpoint
      end

      assert count(user) == 4
    end

    @tag req: "PN-16"
    test "PN-16 administrators extend the allowlist, which takes host names only" do
      admin = user_with_role_fixture(:administrator)
      endpoint = "https://ntfy.example.org/up/abc"

      assert Push.subscribe(admin, "s", browser(endpoint)) == {:error, :not_allowed}

      services = Settings.get(:push_services) <> "\nntfy.example.org"
      assert {:ok, _} = Settings.update_settings(admin, %{"push_services" => services})
      assert {:ok, _} = Push.subscribe(admin, "s", browser(endpoint))

      assert {:error, changeset} =
               Settings.update_settings(admin, %{"push_services" => "https://x.org/path"})

      assert errors_on(changeset).push_services != []
    end
  end

  describe "ending (PN-13)" do
    @tag req: "PN-13"
    test "PN-13 signing out deletes the subscriptions of that session only" do
      user = user_fixture()
      {token, socket_id} = session(user)
      {_other, other_id} = session(user)
      {:ok, _} = Push.subscribe(user, socket_id, browser())
      {:ok, kept} = Push.subscribe(user, other_id, browser())

      :ok = Accounts.delete_user_session_token(token)

      assert Enum.map(Push.list_subscriptions(user), & &1.id) == [kept.id]
    end

    @tag req: "PN-13"
    test "PN-13 a password change keeps only the subscriptions of the session that made it" do
      user = user_fixture(%{password: "the old passphrase"})
      {token, socket_id} = session(user)
      {_other, other_id} = session(user)
      {:ok, kept} = Push.subscribe(user, socket_id, browser())
      {:ok, _} = Push.subscribe(user, other_id, browser())

      {:ok, _} =
        Accounts.update_user_password(
          user,
          %{"current_password" => "the old passphrase", "password" => "a brand new passphrase"},
          token
        )

      assert Enum.map(Push.list_subscriptions(user), & &1.id) == [kept.id]
    end

    @tag req: "PN-13"
    test "PN-13 a password reset, a ban and account deletion end every subscription" do
      reset = user_fixture()
      {:ok, _} = Push.subscribe(reset, "s", browser())
      {:ok, _} = Accounts.reset_user_password(reset, %{password: "a brand new passphrase"})
      assert count(reset) == 0

      moderator = user_with_role_fixture(:administrator)
      banned = user_fixture()
      {:ok, _} = Push.subscribe(banned, "s", browser())
      {:ok, _} = Accounts.ban_user(moderator, banned, nil)
      assert count(banned) == 0

      leaving = user_fixture(%{password: "the old passphrase"})
      {:ok, _} = Push.subscribe(leaving, "s", browser())
      {:ok, _} = Accounts.delete_user(leaving, "the old passphrase")
      assert count(leaving) == 0
    end

    @tag req: "PN-14"
    test "PN-14 rotating the VAPID keys ends every subscription on the server" do
      {:ok, _} = Push.subscribe(user_fixture(), "s", browser())
      {:ok, _} = Push.subscribe(user_fixture(), "s", browser())

      capture_io(fn -> Release.rotate_push_keys() end)

      assert Repo.aggregate(Subscription, :count) == 0

      assert [%{change: "push.rotate_keys", after: %{"subscriptions_ended" => 2}} | _] =
               Audit.list_entries()
    end
  end
end

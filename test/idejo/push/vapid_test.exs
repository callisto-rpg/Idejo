# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.VapidTest do
  # Not async: replaces the server's push keys and settings, which every test shares.
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query
  import ExUnit.CaptureIO
  import Idejo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Idejo.Audit
  alias Idejo.Push
  alias Idejo.Push.Vapid
  alias Idejo.Release
  alias Idejo.Repo
  alias Idejo.Settings.Setting

  describe "keys" do
    @tag req: "PN-14"
    test "PN-14 every install has a P-256 key pair, the private half encrypted in settings" do
      assert {:ok, %{public: public, private: private}} = Vapid.keys()

      assert <<4, _point::binary-size(64)>> = public
      assert byte_size(private) == 32
      assert {^public, _} = :crypto.generate_key(:ecdh, :prime256v1, private)

      assert Vapid.public_key() == Base.url_encode64(public, padding: false)
      stored = Repo.get!(Setting, "vapid_private_key").value
      refute stored =~ Base.url_encode64(private, padding: false)
    end

    @tag req: "PN-14"
    test "PN-14 the command line prints the public key" do
      assert capture_io(fn -> Release.push_key() end) == Vapid.public_key() <> "\n"
    end

    @tag req: "PN-14"
    test "PN-14 the command line rotates the keys, audited without an admin" do
      {:ok, before} = Vapid.keys()

      output = capture_io(fn -> Release.rotate_push_keys() end)

      {:ok, now} = Vapid.keys()
      refute now.public == before.public
      assert output =~ Vapid.public_key()
      assert output =~ "Every browser's push subscription has ended"

      assert [%{change: "push.rotate_keys", admin_id: nil, after: after_} | _] =
               Audit.list_entries()

      assert after_ == %{"public_key" => Vapid.public_key()}
      refute inspect(Audit.list_entries()) =~ Base.url_encode64(now.private, padding: false)
    end

    @tag req: "PN-14"
    test "PN-14 keys that can no longer be decrypted fail the health check" do
      Repo.update_all(from(s in Setting, where: s.key == "vapid_private_key"),
        set: [value: "not encrypted with this server's key"]
      )

      assert Vapid.keys() == {:error, :unreadable}
      assert {"push keys", :error, detail} = List.keyfind(Release.health_checks(), "push keys", 0)
      assert detail =~ "rotate-push-keys"

      {:ok, _} = Release.rotate_push_keys!()
      assert {"push keys", :ok, _} = List.keyfind(Release.health_checks(), "push keys", 0)
    end
  end

  describe "switch" do
    @tag req: "PN-19"
    test "PN-19 push notifications are on by default; administrators turn them off", %{
      conn: conn
    } do
      assert Push.enabled?()

      admin = user_with_role_fixture(:administrator)
      {:ok, lv, _html} = conn |> log_in_user(admin) |> live(~p"/admin")

      lv |> form("#settings-form", settings: %{push_enabled: "off"}) |> render_submit()

      refute Push.enabled?()

      assert [%{change: "settings.update", after: %{"push_enabled" => "off"}} | _] =
               Audit.list_entries()
    end
  end
end

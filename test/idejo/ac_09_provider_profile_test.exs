# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AC09ProviderProfileTest do
  @moduledoc """
  AC-09 with the community menu (steward decisions, 2026-11-06): a new member starts with the
  provider's public username and picture; linking an existing account offers the provider
  this account's (it keeps what it lacks).
  """
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Accounts
  alias Idejo.Accounts.{OIDC, User}
  alias Idejo.{Community, FakeOIDCProvider}

  @moduletag req: "AC-09"

  setup do
    provider = FakeOIDCProvider.start!()
    previous = Application.get_env(:idejo, :community)
    Application.put_env(:idejo, :community, url: "http://hub.test/internal/community")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:idejo, :community, previous),
        else: Application.delete_env(:idejo, :community)
    end)

    %{issuer_host: URI.parse(provider.issuer).host, test_pid: self()}
  end

  defp provider_profile(test_pid, answer) do
    Req.Test.stub(Community, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {conn.method, conn.host, conn.request_path, conn.query_string, raw})

      case {conn.method, conn.request_path} do
        {"GET", "/internal/community/profile"} ->
          Req.Test.json(conn, answer)

        {"POST", "/internal/community/profile"} ->
          Req.Test.json(conn, answer)

        {"GET", "/account/pictures/" <> _} ->
          Plug.Conn.send_resp(conn, 200, File.read!(image_file(:png)))
      end
    end)
  end

  defp claims(sub),
    do: %{
      "iss" => OIDC.config()[:issuer],
      "sub" => sub,
      "email" => "#{sub}@mail.test",
      "email_verified" => true,
      "name" => "Some Name",
      "preferred_username" => "#{sub}@mail.test"
    }

  test "AC-09 a new member gets the provider's username and picture", %{
    issuer_host: host,
    test_pid: test_pid
  } do
    provider_profile(test_pid, %{
      "username" => "Ada_Public",
      "picture" => "http://#{host}/account/pictures/k1.webp"
    })

    assert {:ok, %User{} = user, :new} = OIDC.sign_in(claims("ada"))
    assert user.username == "Ada_Public"
    assert user.avatar_id
    assert_received {"GET", _, "/internal/community/profile", "subject=ada", _}
    assert_received {"GET", ^host, "/account/pictures/k1.webp", _, _}
  end

  test "AC-09 a picture elsewhere than the provider's host, or a bad username: not used", %{
    test_pid: test_pid
  } do
    provider_profile(test_pid, %{
      "username" => "bob@mail.test",
      "picture" => "http://elsewhere.test/evil.webp"
    })

    assert {:ok, %User{} = user, :new} = OIDC.sign_in(claims("bob"))
    assert user.username == "Some_Name"
    refute user.avatar_id
    refute_received {"GET", "elsewhere.test", _, _, _}
  end

  test "AC-09 linking offers the provider this account's username and picture", %{
    test_pid: test_pid
  } do
    provider_profile(test_pid, %{"username" => "kim_local", "picture" => nil})
    user = user_fixture(%{username: "kim_local"})
    {:ok, user} = Accounts.set_avatar(user, image_file(:png))
    user = Idejo.Repo.get!(User, user.id)

    assert {:ok, _identity} = OIDC.link(user, claims("kim"))

    assert_received {"POST", _, "/internal/community/profile", _, body}
    sent = Jason.decode!(body)
    assert sent["subject"] == "kim"
    assert sent["username"] == "kim_local"
    assert <<"RIFF", _::binary-size(4), "WEBP", _::binary>> = Base.decode64!(sent["picture"])
  end

  test "AC-09 with no community address, nothing is asked", %{test_pid: test_pid} do
    Application.delete_env(:idejo, :community)
    provider_profile(test_pid, %{})
    assert {:ok, %User{username: "Some_Name"}, :new} = OIDC.sign_in(claims("cy"))
    refute_received {_, _, _, _, _}
  end
end

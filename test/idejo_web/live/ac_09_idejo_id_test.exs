# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AC09IdejoIdTest do
  @moduledoc """
  AC-09 (steward decisions, 2026-11-06): an administrator connects the server to an idejo ID
  registry from Admin → idejo ID, proving the server answers at its own address, and may then
  ask to be listed in the registry's directory; without the connection it cannot.
  """
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query
  import Idejo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Idejo.Accounts.{OIDC, OIDCRegistry}
  alias Idejo.Audit.Entry
  alias Idejo.Repo

  @moduletag req: "AC-09"

  setup %{conn: conn} do
    Req.Test.set_req_test_to_shared()
    previous = Application.get_env(:idejo, :oidc)
    Application.delete_env(:idejo, :oidc)

    on_exit(fn ->
      OIDCRegistry.forget()
      if previous, do: Application.put_env(:idejo, :oidc, previous)
    end)

    admin = user_with_role_fixture(:administrator)
    %{conn: log_in_user(conn, admin), admin: admin, test_pid: self()}
  end

  # The registry: it fetches the proof from this server before answering credentials.
  defp registry(test_pid) do
    {:ok, listing} = Agent.start_link(fn -> "none" end)

    Req.Test.stub(OIDCRegistry, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = if raw == "", do: %{}, else: Jason.decode!(raw)

      send(
        test_pid,
        {:registry, conn.method, conn.request_path, body,
         Plug.Conn.get_req_header(conn, "authorization")}
      )

      answer(conn, {conn.method, conn.request_path}, body, listing)
    end)
  end

  defp answer(conn, {"POST", "/account/api/registrations"}, _body, _listing),
    do: Req.Test.json(conn, %{"registration" => "reg-key", "proof" => "the-proof"})

  defp answer(conn, {"POST", "/account/api/registrations/verify"}, body, _listing) do
    served = Phoenix.ConnTest.build_conn() |> get("/.well-known/idejo-id-registration")

    if body["registration"] == "reg-key" and served.status == 200 and
         served.resp_body == "the-proof" do
      Req.Test.json(conn, %{
        "issuer" => "https://login.idejo.test",
        "client_id" => "client-1",
        "client_secret" => "secret-1",
        "label" => "idejo ID",
        "sign_up_url" => "https://login.idejo.test/account/sign-up",
        "directory_url" => "https://forums.idejo.test/"
      })
    else
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{"error" => "proof_failed", "message" => "The proof did not match."})
    end
  end

  defp answer(conn, {"GET", "/account/api/listing"}, _body, listing),
    do: Req.Test.json(conn, %{"listing" => Agent.get(listing, & &1)})

  defp answer(conn, {"PUT", "/account/api/listing"}, body, listing) do
    status = if body["listed"], do: "requested", else: "none"
    Agent.update(listing, fn _ -> status end)
    Req.Test.json(conn, %{"listing" => status})
  end

  test "AC-09 the administrator connects to idejo ID, and members can sign in with it", %{
    conn: conn,
    test_pid: test_pid
  } do
    registry(test_pid)
    refute OIDC.enabled?()

    {:ok, view, html} = live(conn, ~p"/admin/idejo-id")
    assert html =~ "Connect to idejo ID (login.idejo.test)"
    # Listing needs the connection first.
    assert html =~ "Only forums that sign in with idejo ID can be listed"
    refute has_element?(view, "#idejo-id-listing")

    view |> element("#idejo-id-connect-button") |> render_click()
    assert render(view) =~ "Connected: members can now sign in with idejo ID."

    assert_received {:registry, "POST", "/account/api/registrations",
                     %{"host" => "localhost", "name" => _}, _}

    assert_received {:registry, "POST", "/account/api/registrations/verify",
                     %{"registration" => "reg-key"}, _}

    # The proof is served only while connecting.
    assert get(build_conn(), "/.well-known/idejo-id-registration").status == 404

    assert OIDC.enabled?()
    assert OIDC.label() == "idejo ID"
    assert OIDC.sign_up_url() == "https://login.idejo.test/account/sign-up"
    assert Idejo.Community.directory_url() == "https://forums.idejo.test/"

    # Kept in the database, the secret encrypted; read again after a restart.
    secret =
      Repo.one(
        from s in Idejo.Settings.Setting,
          where: s.key == "oidc_registration_secret",
          select: s.value
      )

    refute secret =~ "secret-1"
    OIDCRegistry.forget()
    refute OIDC.enabled?()
    OIDCRegistry.load()
    assert OIDC.config()[:client_secret] == "secret-1"

    entry = Repo.one!(from e in Entry, where: e.change == "oidc.connect")
    refute inspect(entry) =~ "secret-1"
  end

  test "AC-09 a connected forum asks to be listed; disconnecting leaves the directory", %{
    conn: conn,
    admin: admin,
    test_pid: test_pid
  } do
    registry(test_pid)
    {:ok, _label} = OIDCRegistry.connect(admin)

    {:ok, view, _html} = live(conn, ~p"/admin/idejo-id")
    assert render(view) =~ "Not listed."

    view |> form("#idejo-id-listing") |> render_change(%{"listed" => "true"})
    assert render(view) =~ "Waiting for the directory&#39;s approval."
    assert_received {:registry, "PUT", "/account/api/listing", %{"listed" => true}, [auth]}
    assert auth == "Basic " <> Base.encode64("client-1:secret-1")

    view |> element("#idejo-id-disconnect") |> render_click()
    assert_received {:registry, "PUT", "/account/api/listing", %{"listed" => false}, _}
    refute OIDC.enabled?()
    assert render(view) =~ "Connect to idejo ID"
  end

  test "AC-09 a registry's refusal is shown and nothing is kept", %{conn: conn} do
    Req.Test.stub(OIDCRegistry, fn conn ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{
        "error" => "invalid_host",
        "message" => "Give the forum's own host name."
      })
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/idejo-id")
    view |> element("#idejo-id-connect-button") |> render_click()
    assert render(view) =~ "idejo ID answered: Give the forum&#39;s own host name."
    refute OIDC.enabled?()
  end

  test "AC-09 a provider set by the environment wins: connecting is not offered", %{conn: conn} do
    Application.put_env(:idejo, :oidc,
      issuer: "https://id.example.test",
      client_id: "c",
      client_secret: "s",
      label: "Example ID"
    )

    on_exit(fn -> Application.delete_env(:idejo, :oidc) end)

    {:ok, _view, html} = live(conn, ~p"/admin/idejo-id")
    assert html =~ "Members sign in with Example ID, set by this server&#39;s environment"
    refute html =~ "idejo-id-connect-button"
    refute html =~ "idejo-id-listing"
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AD15HealthTest do
  @moduledoc """
  AD-15: `GET /health` answers JSON `{status, version, checks: {database, migrations}}`,
  200 when every check is ok, else 503; no sign-in, no session, no personal data.
  """
  # One test turns the setup redirect on, which is global.
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures

  alias IdejoWeb.Plugs.RequireSetup

  # A repository that was never started: every query fails, as with the database down.
  defmodule DownRepo do
    use Ecto.Repo, otp_app: :idejo, adapter: Ecto.Adapters.Postgres
  end

  defp health(conn \\ build_conn(), checks \\ nil) do
    conn = if checks, do: put_private(conn, :idejo_health, checks), else: conn
    get(conn, ~p"/health")
  end

  @tag req: "AD-15"
  test "AD-15 healthy: 200 with exactly the documented keys" do
    conn = health()

    assert conn.status == 200
    assert ["application/json; charset=utf-8"] = get_resp_header(conn, "content-type")
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert Jason.decode!(conn.resp_body) == %{
             "status" => "ok",
             "version" => Idejo.Health.version(),
             "checks" => %{"database" => "ok", "migrations" => "ok"}
           }

    assert Idejo.Health.version() == to_string(Application.spec(:idejo, :vsn))
  end

  @tag req: "AD-15"
  test "AD-15 503 when the database does not answer" do
    conn = health(build_conn(), repo: DownRepo)

    assert conn.status == 503

    assert %{
             "status" => "error",
             "checks" => %{"database" => "error", "migrations" => "error"}
           } = Jason.decode!(conn.resp_body)
  end

  @tag :tmp_dir
  @tag req: "AD-15"
  test "AD-15 503 while a migration of the release is not applied", %{tmp_dir: dir} do
    for file <- Path.wildcard("priv/repo/migrations/*.exs"),
        do: File.cp!(file, Path.join(dir, Path.basename(file)))

    assert Jason.decode!(health(build_conn(), migrations_path: dir).resp_body)["status"] == "ok"

    File.write!(Path.join(dir, "99991231000000_not_run_yet.exs"), "")
    conn = health(build_conn(), migrations_path: dir)

    assert conn.status == 503

    assert %{"status" => "error", "checks" => %{"database" => "ok", "migrations" => "pending"}} =
             Jason.decode!(conn.resp_body)
  end

  @tag req: "AD-15"
  test "AD-15 no session, no cookie, nothing personal, signed in or not" do
    owner = user_with_role_fixture(:owner, %{display_name: "Olga Owner"})

    for conn <- [build_conn(), log_in_user(build_conn(), owner)] do
      conn = health(conn)
      assert conn.status == 200
      assert get_resp_header(conn, "set-cookie") == []
      assert conn.resp_cookies == %{}
      refute conn.resp_body =~ owner.email
      refute conn.resp_body =~ owner.username
      refute conn.resp_body =~ "Olga"
      # Only the documented words.
      body = Jason.decode!(conn.resp_body)
      assert Map.keys(body) |> Enum.sort() == ["checks", "status", "version"]
      assert Map.keys(body["checks"]) |> Enum.sort() == ["database", "migrations"]
    end

    # A failure says no more than "error".
    body = health(build_conn(), repo: DownRepo).resp_body
    refute body =~ "DownRepo"
    refute body =~ "not started"
  end

  @tag req: "AD-15"
  test "AD-15 rate-limited like every request, with room for health checks" do
    Application.put_env(:idejo, :rate_limits, enabled: true)
    on_exit(fn -> Application.put_env(:idejo, :rate_limits, enabled: false) end)

    # The shared per-address limit (SP-05): a check every 10 s from the container and one a
    # minute from outside are 7 a minute, far below it.
    {limit, window} = Idejo.RateLimit.limit(:request)
    assert window == 60_000 and limit >= 60

    # An address no other test uses (RFC 5737), so no other counter is touched.
    conn = %{build_conn() | remote_ip: {203, 0, 113, 15}}
    # All in one window (fixed minutes), so the count never starts again midway.
    Idejo.RateLimitWindow.fresh(:request)
    for _ <- 1..limit, do: assert(health(conn).status == 200)
    assert health(conn).status == 429
  end

  @tag req: "AD-15"
  test "AD-15 answers before the setup wizard has run" do
    Application.put_env(:idejo, :setup_redirect, true)
    RequireSetup.forget()

    on_exit(fn ->
      Application.put_env(:idejo, :setup_redirect, false)
      RequireSetup.forget()
    end)

    assert Idejo.Setup.needed?()
    assert redirected_to(get(build_conn(), ~p"/")) == ~p"/setup"
    assert health().status == 200
  end
end

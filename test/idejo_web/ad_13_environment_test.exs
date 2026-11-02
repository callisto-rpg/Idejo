# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AD13EnvironmentTest do
  @moduledoc """
  AD-13: all runtime configuration from environment variables: a required host, optional
  SMTP defaults the admin panel overrides, a WebSocket origin check that follows the host,
  and every variable documented in `deploy/.env.example`.
  """
  # Changes environment variables and application settings shared by every test.
  use IdejoWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Idejo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Idejo.Accounts.UserNotifier
  alias Idejo.Audit
  alias Idejo.Mailer
  alias Idejo.Settings
  alias Idejo.SMTPCapture
  alias Phoenix.Socket.Transport

  @base %{
    "PHX_HOST" => "a.idejo.test",
    "DATABASE_URL" => "ecto://idejo:secret@db/idejo",
    "SECRET_KEY_BASE" => String.duplicate("k", 64)
  }

  @smtp_names ~w(HOST PORT SECURITY USERNAME PASSWORD FROM)

  # Reads config/runtime.exs as production would, with exactly these variables set (and
  # the SMTP ones unset unless given), then puts the environment back.
  defp runtime(env) do
    names = Map.keys(@base) ++ Enum.map(@smtp_names, &("IDEJO_SMTP_" <> &1)) ++ ["POOL_SIZE"]
    saved = Map.new(names, &{&1, System.get_env(&1)})

    try do
      Enum.each(names, &System.delete_env/1)

      for {name, value} <- Map.merge(@base, env), value != nil, do: System.put_env(name, value)

      Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)[:idejo]
    after
      for {name, value} <- saved do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end
  end

  defp use_smtp_adapter(_context) do
    previous = Application.get_env(:idejo, Mailer)
    Application.put_env(:idejo, Mailer, adapter: Swoosh.Adapters.SMTP)
    on_exit(fn -> Application.put_env(:idejo, Mailer, previous) end)
  end

  defp put_smtp_environment(env) do
    Application.put_env(:idejo, :smtp_environment, env)
    on_exit(fn -> Application.delete_env(:idejo, :smtp_environment) end)
  end

  @tag req: "AD-13"
  test "AD-13 production does not start without PHX_HOST, and follows it" do
    for missing <- [nil, "", "   "] do
      assert_raise RuntimeError, ~r/PHX_HOST is missing/, fn ->
        runtime(%{"PHX_HOST" => missing})
      end
    end

    config = runtime(%{})
    endpoint = config[IdejoWeb.Endpoint]
    assert endpoint[:url][:host] == "a.idejo.test"
    assert endpoint[:check_origin] == ["https://a.idejo.test"]
    assert config[:base_uri] == "https://a.idejo.test"
    refute inspect(config) =~ "example.com"

    # Empty optional values count as unset.
    assert runtime(%{"POOL_SIZE" => ""})[Idejo.Repo][:pool_size] == 10
    assert runtime(%{"POOL_SIZE" => "4"})[Idejo.Repo][:pool_size] == 4
  end

  @tag req: "AD-13"
  test "AD-13 a live connection from another origin is refused" do
    origins = runtime(%{})[IdejoWeb.Endpoint][:check_origin]

    check = fn origin ->
      :get
      |> build_conn("/live/websocket")
      |> put_req_header("origin", origin)
      |> Transport.check_origin(
        Phoenix.LiveView.Socket,
        IdejoWeb.Endpoint,
        [check_origin: origins],
        & &1
      )
    end

    refute check.("https://a.idejo.test").halted

    capture_log(fn ->
      for origin <- ["https://b.idejo.test", "http://a.idejo.test", "https://idejo.test"] do
        conn = check.(origin)
        assert conn.halted and conn.status == 403, origin
      end
    end)
  end

  @tag req: "AD-13"
  test "AD-13 the SMTP variables are read only with a host, and checked at boot" do
    refute runtime(%{"IDEJO_SMTP_USERNAME" => "forum"})[:smtp_environment]
    refute runtime(%{"IDEJO_SMTP_HOST" => ""})[:smtp_environment]

    assert runtime(%{"IDEJO_SMTP_HOST" => "smtp.idejo.test"})[:smtp_environment] == [
             host: "smtp.idejo.test",
             port: 587,
             security: "starttls",
             username: "",
             password: "",
             from: nil
           ]

    env =
      runtime(%{
        "IDEJO_SMTP_HOST" => "smtp.idejo.test",
        "IDEJO_SMTP_PORT" => "465",
        "IDEJO_SMTP_USERNAME" => "forum",
        "IDEJO_SMTP_PASSWORD" => "env-pass",
        "IDEJO_SMTP_FROM" => "forum@idejo.test"
      })[:smtp_environment]

    assert env[:security] == "tls"

    assert {env[:username], env[:password], env[:from]} ==
             {"forum", "env-pass", "forum@idejo.test"}

    assert_raise RuntimeError, ~r/IDEJO_SMTP_PORT/, fn ->
      runtime(%{"IDEJO_SMTP_HOST" => "smtp.idejo.test", "IDEJO_SMTP_PORT" => "smtp"})
    end

    assert_raise RuntimeError, ~r/IDEJO_SMTP_SECURITY/, fn ->
      runtime(%{"IDEJO_SMTP_HOST" => "smtp.idejo.test", "IDEJO_SMTP_SECURITY" => "ssl3"})
    end
  end

  describe "sending" do
    # The admin first: making an account sends an email.
    setup do
      %{admin: user_with_role_fixture(:administrator)}
    end

    setup :use_smtp_adapter

    @tag req: "AD-13"
    test "AD-13 email uses the environment's SMTP server until the panel has a host", %{
      admin: admin
    } do
      env_port = SMTPCapture.start!(auth: {"env-user", "env-pass"})

      put_smtp_environment(
        host: "localhost",
        port: env_port,
        security: "none",
        username: "env-user",
        password: "env-pass",
        from: "env@idejo.test"
      )

      assert {:ok, _} = UserNotifier.deliver_test_email("ada@idejo.test")
      assert_receive {:smtp_mail, "env@idejo.test", ["ada@idejo.test"], data}, 5_000
      assert data =~ "From: Idejo <env@idejo.test>"

      # The panel gets a host: its settings, all of them, and its sender.
      panel_port = SMTPCapture.start!(auth: {"panel-user", "panel-pass"})

      {:ok, _} =
        Settings.update_settings(admin, %{
          "mail_from" => "panel@idejo.test",
          "smtp_host" => "localhost",
          "smtp_port" => "#{panel_port}",
          "smtp_security" => "none",
          "smtp_username" => "panel-user",
          "smtp_password" => "panel-pass"
        })

      assert {:ok, _} = UserNotifier.deliver_test_email("bea@idejo.test")
      assert_receive {:smtp_mail, "panel@idejo.test", ["bea@idejo.test"], _data}, 5_000
      refute_received {:smtp_mail, "env@idejo.test", _, _}

      # Never a mix: with a panel host and no panel login, the environment's login is not used.
      settings = Mailer.smtp_settings(%{Settings.all() | smtp_username: "", smtp_password: ""})
      assert {settings.smtp_username, settings.smtp_password} == {"", ""}
    end

    @tag req: "AD-13"
    test "AD-13 the environment's password never shows in logs, audit entries or the panel",
         %{conn: conn, admin: admin} do
      port = SMTPCapture.start!(auth: {"env-user", "another-pass"})

      put_smtp_environment(
        host: "localhost",
        port: port,
        security: "none",
        username: "env-user",
        password: "env-secret-pass",
        from: nil
      )

      log =
        capture_log(fn ->
          assert {:error, _reason} = UserNotifier.deliver_test_email("ada@idejo.test")
        end)

      refute log =~ "env-secret-pass"

      {:ok, view, html} = live(log_in_user(conn, admin), ~p"/admin/email")
      assert has_element?(view, "#email-environment", "localhost (port #{port})")
      refute html =~ "env-secret-pass"
      refute html =~ "env-user"

      html = view |> element("#send-test-email") |> render_click()
      refute html =~ "env-secret-pass"
      refute render_async(view) =~ "env-secret-pass"

      refute inspect(Audit.list_entries()) =~ "env-secret-pass"
      refute inspect(Idejo.Repo.all(Settings.Setting)) =~ "env-secret-pass"
      # Nothing from the environment is copied into the settings.
      assert Settings.get(:smtp_host) == ""
    end
  end

  @tag req: "AD-13"
  test "AD-13 every environment variable the app reads is in deploy/.env.example" do
    sources = ["config/runtime.exs" | Path.wildcard("lib/**/*.ex")]

    read =
      for path <- sources,
          # Comments aside (runtime.exs keeps Phoenix's examples).
          source = path |> File.read!() |> String.replace(~r/^\s*#.*$/m, ""),
          [_, name] <- Regex.scan(~r/System\.(?:get_env|fetch_env!?)\("([A-Z0-9_]+)"/, source),
          # IDEJO_SMTP_ + a name: listed below.
          not String.ends_with?(name, "_"),
          into: MapSet.new(),
          do: name

    smtp = for name <- @smtp_names, into: MapSet.new(), do: "IDEJO_SMTP_" <> name
    read = MapSet.union(read, smtp)
    assert "PHX_HOST" in read

    example = File.read!("deploy/.env.example")
    missing = for name <- read, not (example =~ ~r/\b#{name}=/), do: name
    assert missing == [], "not in deploy/.env.example: #{inspect(missing)}"

    # The bundled Compose file passes the optional ones on to the app.
    compose = File.read!("deploy/docker-compose.yml")
    for name <- smtp, do: assert(compose =~ "#{name}: ${#{name}:-}", name)

    deploying = File.read!("docs/deploying.md")
    for name <- read, do: assert(deploying =~ "`#{name}`", "docs/deploying.md: #{name}")
  end
end

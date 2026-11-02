# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AD16ProxyTest do
  @moduledoc """
  AD-16: the bundled Caddy stays the default; a documented second Compose file runs the app
  behind an external proxy. X-Forwarded-For, -Proto and -Host are believed only from the
  addresses in `IDEJO_TRUSTED_PROXIES` (private networks while it is unset), through one
  check (`IdejoWeb.Plugs.ClientIp.trusted?/1`) that the rate limits follow too.
  """
  # Changes the trusted proxies and turns rate limits on: global settings.
  use IdejoWeb.ConnCase, async: false

  alias Idejo.RateLimit
  alias IdejoWeb.Plugs.ClientIp

  setup do
    previous = Application.get_env(:idejo, :trusted_proxies)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:idejo, :trusted_proxies, previous),
        else: Application.delete_env(:idejo, :trusted_proxies)
    end)
  end

  defp trust(proxies), do: Application.put_env(:idejo, :trusted_proxies, proxies)

  defp from(peer, headers) do
    conn = %{build_conn(:get, "/") | remote_ip: peer}
    Enum.reduce(headers, conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
  end

  @forwarded [
    {"x-forwarded-for", "203.0.113.9"},
    {"x-forwarded-proto", "https"},
    {"x-forwarded-host", "a.idejo.test"}
  ]

  defp applied?(conn) do
    conn = ClientIp.call(conn, [])
    {conn.remote_ip, conn.scheme, conn.host} == {{203, 0, 113, 9}, :https, "a.idejo.test"}
  end

  defp ignored?(conn) do
    after_ = ClientIp.call(conn, [])
    {after_.remote_ip, after_.scheme, after_.host} == {conn.remote_ip, :http, "www.example.com"}
  end

  @tag req: "AD-16"
  test "AD-16 unset: private-network peers are trusted, as before, and nobody else" do
    Application.delete_env(:idejo, :trusted_proxies)

    # The bundled Caddy, also as an IPv4-mapped IPv6 address, and a ULA peer.
    for peer <- [
          {172, 18, 0, 3},
          {0, 0, 0, 0, 0, 0xFFFF, 0xAC12, 0x0003},
          {0xFD00, 0, 0, 0, 0, 0, 0, 1}
        ] do
      assert applied?(from(peer, @forwarded)), inspect(peer)
    end

    # From the internet, the headers are ignored.
    assert ignored?(from({198, 51, 100, 7}, @forwarded))
    # Unset keeps today's rule: the rightmost X-Forwarded-For address, which Caddy writes.
    conn = ClientIp.call(from({10, 0, 0, 2}, [{"x-forwarded-for", "1.2.3.4, 203.0.113.9"}]), [])
    assert conn.remote_ip == {203, 0, 113, 9}
  end

  @tag req: "AD-16"
  test "AD-16 set: only the listed proxies are trusted" do
    trust([{{198, 51, 100, 0}, 24}, {{0x2001, 0xDB8, 0, 0, 0, 0, 0, 0}, 32}])

    assert applied?(from({198, 51, 100, 7}, @forwarded))
    assert applied?(from({0x2001, 0xDB8, 1, 2, 3, 4, 5, 6}, @forwarded))
    assert applied?(from({0, 0, 0, 0, 0, 0xFFFF, 0xC633, 0x6407}, @forwarded))

    # A private peer is no longer trusted once a list is given, nor anything outside it.
    assert ignored?(from({172, 18, 0, 3}, @forwarded))
    assert ignored?(from({198, 51, 101, 7}, @forwarded))
    assert ignored?(from({0x2001, 0xDB9, 0, 0, 0, 0, 0, 1}, @forwarded))

    assert ClientIp.trusted?({198, 51, 100, 255})
    refute ClientIp.trusted?({127, 0, 0, 1})
  end

  @tag req: "AD-16"
  test "AD-16 a chain of trusted proxies leads to the visitor; bad values change nothing" do
    trust([{{10, 0, 0, 0}, 8}])

    # Visitor, then an outer proxy of ours, then the one that reached the app.
    conn =
      ClientIp.call(
        from({10, 0, 0, 2}, [{"x-forwarded-for", "6.6.6.6, 203.0.113.9, 10.1.1.1"}]),
        []
      )

    assert conn.remote_ip == {203, 0, 113, 9}

    for {name, value} <- [
          {"x-forwarded-for", "not-an-address"},
          {"x-forwarded-proto", "gopher"},
          {"x-forwarded-host", "evil.test/path"},
          {"x-forwarded-host", "<script>"}
        ] do
      assert ignored?(from({10, 0, 0, 2}, [{name, value}])), "#{name}: #{value}"
    end

    # A host with a port: the name only.
    assert ClientIp.call(from({10, 0, 0, 2}, [{"x-forwarded-host", "A.idejo.test:8443"}]), []).host ==
             "a.idejo.test"
  end

  @tag req: "AD-16"
  test "AD-16 https is forced after the trust check: a visitor cannot claim it" do
    ssl = Plug.SSL.init(host: "a.idejo.test", exclude: [])
    run = &(&1 |> ClientIp.call([]) |> Plug.SSL.call(ssl))

    trust([{{10, 0, 0, 2}, 32}])
    proto = [{"x-forwarded-proto", "https"}]

    # From the trusted proxy: https, served.
    refute run.(from({10, 0, 0, 2}, proto)).halted

    # From anyone else the header is ignored: redirected to https.
    conn = run.(from({198, 51, 100, 7}, proto))
    assert conn.halted and conn.status == 301
    assert get_resp_header(conn, "location") == ["https://a.idejo.test/"]

    # The endpoint plugs Plug.SSL itself, after ClientIp, and believes no header itself.
    endpoint = File.read!("lib/idejo_web/endpoint.ex")
    {client_ip, _} = :binary.match(endpoint, "plug IdejoWeb.Plugs.ClientIp")
    {ssl_plug, _} = :binary.match(endpoint, "plug Plug.SSL")
    {static, _} = :binary.match(endpoint, "plug Plug.Static")
    assert client_ip < ssl_plug and ssl_plug < static

    prod = Config.Reader.read!("config/prod.exs", env: :prod)
    refute prod[:idejo][IdejoWeb.Endpoint][:force_ssl]
    refute Keyword.has_key?(prod[:idejo][:force_ssl], :rewrite_on)
  end

  @tag req: "AD-16"
  test "AD-16 rate limits count the address the same check gives" do
    Application.put_env(:idejo, :rate_limits, enabled: true)
    on_exit(fn -> Application.put_env(:idejo, :rate_limits, enabled: false) end)
    trust([{{192, 0, 2, 10}, 32}])

    {limit, _window} = RateLimit.limit(:sign_in)

    attempt = fn peer, visitor ->
      %{build_conn() | remote_ip: peer}
      |> put_req_header("x-forwarded-for", visitor)
      |> post(~p"/users/sign-in", %{
        "user" => %{"email" => "x@idejo.test", "password" => "wrong password!"}
      })
    end

    # Through the trusted proxy, each visitor has a counter of their own.
    for _ <- 1..limit, do: assert(attempt.({192, 0, 2, 10}, "192.0.2.101").status == 200)
    assert attempt.({192, 0, 2, 10}, "192.0.2.101").status == 429
    assert attempt.({192, 0, 2, 10}, "192.0.2.102").status == 200

    # From an untrusted peer, the header is ignored: one counter, whatever it claims.
    for n <- 1..limit, do: assert(attempt.({192, 0, 2, 20}, "192.0.2.#{110 + n}").status == 200)
    assert attempt.({192, 0, 2, 20}, "192.0.2.199").status == 429
  end

  @tag req: "AD-16"
  test "AD-16 a malformed IDEJO_TRUSTED_PROXIES stops the boot with a message" do
    read = fn value ->
      saved = System.get_env("IDEJO_TRUSTED_PROXIES")
      System.put_env("IDEJO_TRUSTED_PROXIES", value)

      try do
        Config.Reader.read!("config/runtime.exs", env: :test)[:idejo][:trusted_proxies]
      after
        if saved,
          do: System.put_env("IDEJO_TRUSTED_PROXIES", saved),
          else: System.delete_env("IDEJO_TRUSTED_PROXIES")
      end
    end

    assert read.(" 10.0.0.5 , 172.18.0.0/16,fd00::/8") == [
             {{10, 0, 0, 5}, 32},
             {{172, 18, 0, 0}, 16},
             {{0xFD00, 0, 0, 0, 0, 0, 0, 0}, 8}
           ]

    assert read.("") == nil

    for bad <- [
          "10.0.0",
          "10.0.0.0/33",
          "fd00::/129",
          "proxy.idejo.test",
          "10.0.0.1,,",
          "1.2.3.4/x",
          "1/2/3"
        ] do
      assert_raise RuntimeError, ~r/IDEJO_TRUSTED_PROXIES has an invalid entry/, fn ->
        read.(bad)
      end
    end
  end

  @tag req: "AD-16"
  test "AD-16 the bundled Caddy stays the default; the second Compose file leaves it out" do
    default = File.read!("deploy/docker-compose.yml")
    [_, caddy] = Regex.run(~r/\n  caddy:\n(.*?)\n\S/s, default <> "\nend")
    assert caddy =~ "image: caddy:"
    assert caddy =~ ~s("443:443")
    refute caddy =~ "profiles:"
    assert default =~ "IDEJO_TRUSTED_PROXIES: ${IDEJO_TRUSTED_PROXIES:-}"

    external = File.read!("deploy/docker-compose.external-proxy.yml")
    assert external =~ ~s(caddy:\n    profiles: ["bundled-proxy"])
    assert external =~ ~s("${IDEJO_BIND:-127.0.0.1}:${IDEJO_PORT:-4000}:4000")

    guide = File.read!("docs/deploying.md")
    assert guide =~ "## Running behind your own reverse proxy"
    assert guide =~ "docker-compose.external-proxy.yml"
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.RateLimitTest do
  @moduledoc """
  SP-05 rate limits. Limits are off in the test configuration, so this module turns them on;
  it is not async, as that setting is global. Each test acts from addresses and accounts of
  its own, so the counters of one never touch another.
  """
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Moderation
  alias Idejo.RateLimit
  alias Idejo.Repo
  alias IdejoWeb.Plugs.ClientIp

  setup do
    Application.put_env(:idejo, :rate_limits, enabled: true)
    on_exit(fn -> Application.put_env(:idejo, :rate_limits, enabled: false) end)
  end

  # A documentation address (RFC 5737) of the test's own.
  defp from_ip do
    n = System.unique_integer([:positive])
    %{build_conn() | remote_ip: {198, 51, rem(div(n, 250), 250), rem(n, 250)}}
  end

  @tag req: "SP-05"
  test "SP-05 sign-in attempts are limited per IP address" do
    conn = from_ip()
    {limit, _window} = RateLimit.limit(:sign_in)

    attempt = fn conn ->
      post(conn, ~p"/users/sign-in", %{
        "user" => %{"email" => "x@example.org", "password" => "wrong password!"}
      })
    end

    for _ <- 1..limit, do: assert(attempt.(conn).status == 200)

    refused = attempt.(conn)
    assert refused.status == 429
    assert get_resp_header(refused, "retry-after") == ["60"]
    assert refused.resp_body =~ "Too many requests"

    # Another address is not affected.
    assert attempt.(from_ip()).status == 200
  end

  @tag req: "SP-05"
  test "SP-05 every request is limited per IP address" do
    conn = from_ip()
    {limit, _window} = RateLimit.limit(:request)
    for _ <- 1..limit, do: assert(get(conn, ~p"/robots.txt").status == 200)
    assert get(conn, ~p"/robots.txt").status == 429
  end

  @tag req: "SP-05"
  test "SP-05 the client's address is read from the proxy's header, never from the internet" do
    proxied =
      %{build_conn() | remote_ip: {172, 18, 0, 5}}
      |> put_req_header("x-forwarded-for", "1.2.3.4, 198.51.100.7")
      |> ClientIp.call([])

    assert proxied.remote_ip == {198, 51, 100, 7}

    # Caddy as Bandit sees it on the Compose network: ::ffff:172.18.0.3.
    mapped =
      %{build_conn() | remote_ip: {0, 0, 0, 0, 0, 0xFFFF, 0xAC12, 0x0003}}
      |> put_req_header("x-forwarded-for", "198.51.100.8")
      |> ClientIp.call([])

    assert mapped.remote_ip == {198, 51, 100, 8}

    # A mapped public address is the internet: its header is not believed.
    mapped_public =
      %{build_conn() | remote_ip: {0, 0, 0, 0, 0, 0xFFFF, 0xC633, 0x6409}}
      |> put_req_header("x-forwarded-for", "10.0.0.1")
      |> ClientIp.call([])

    assert mapped_public.remote_ip == {0, 0, 0, 0, 0, 0xFFFF, 0xC633, 0x6409}

    direct =
      %{build_conn() | remote_ip: {198, 51, 100, 9}}
      |> put_req_header("x-forwarded-for", "10.0.0.1")
      |> ClientIp.call([])

    assert direct.remote_ip == {198, 51, 100, 9}
  end

  @tag req: "SP-05"
  test "SP-05 posting is limited per user" do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture()

    {topics, _window} = RateLimit.limit(:new_topic)

    for n <- 1..topics,
        do: {:ok, _} = Forum.create_topic(member, general, %{"title" => "T#{n}", "body" => "B"})

    assert Forum.create_topic(member, general, %{"title" => "One more", "body" => "B"}) ==
             {:error, :rate_limited}

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Busy", "body" => "B"})

    {messages, _window} = RateLimit.limit(:new_message)
    poster = user_fixture()
    for n <- 1..messages, do: {:ok, _} = Forum.post_message(poster, topic, %{"body" => "M#{n}"})
    assert Forum.post_message(poster, topic, %{"body" => "Again"}) == {:error, :rate_limited}

    [message | _] = Forum.list_messages(topic)
    {reports, _window} = RateLimit.limit(:report)
    reporter = user_fixture()

    for _ <- 1..reports do
      {:ok, report} = Moderation.report_message(reporter, message, %{"reason" => "x"})
      Repo.delete!(report)
    end

    assert Moderation.report_message(reporter, message, %{"reason" => "x"}) ==
             {:error, :rate_limited}
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.ClientIp do
  @moduledoc """
  The visitor's real IP address behind the reverse proxy, for rate limits (SP-05).

  In the Compose bundle the app is reachable only through Caddy, which sets
  `X-Forwarded-For` to the address it received the request from and ignores what the
  visitor sent. So when the request comes straight from a private-network peer (the proxy),
  the rightmost address of that header becomes `remote_ip`; otherwise nothing changes, and a
  header sent from the internet is never believed. Off with
  `config :idejo, :behind_proxy, false`.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with true <- Application.get_env(:idejo, :behind_proxy, true),
         true <- private?(unmap(conn.remote_ip)),
         [header | _] <- get_req_header(conn, "x-forwarded-for"),
         {:ok, ip} <- rightmost(header) do
      %{conn | remote_ip: ip}
    else
      _ -> conn
    end
  end

  defp rightmost(header) do
    header
    |> String.split(",")
    |> List.last()
    |> String.trim()
    |> String.to_charlist()
    |> :inet.parse_strict_address()
  end

  # Bandit listens on IPv6 as well, so an IPv4 peer such as Caddy on the Compose network
  # arrives as an IPv4-mapped IPv6 address (::ffff:172.18.0.3).
  defp unmap({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do:
      {Bitwise.bsr(high, 8), Bitwise.band(high, 0xFF), Bitwise.bsr(low, 8),
       Bitwise.band(low, 0xFF)}

  defp unmap(ip), do: ip

  defp private?({10, _, _, _}), do: true
  defp private?({172, b, _, _}) when b in 16..31, do: true
  defp private?({192, 168, _, _}), do: true
  defp private?({127, _, _, _}), do: true
  defp private?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private?({a, _, _, _, _, _, _, _}) when a in 0xFC00..0xFDFF, do: true
  defp private?(_ip), do: false
end

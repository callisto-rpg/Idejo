# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.ClientIp do
  @moduledoc """
  What the reverse proxy in front of the app says about a request, believed only from a
  trusted proxy (SP-05, AD-16): `trusted?/1` is the one check.

  Which peers are trusted:

    * `IDEJO_TRUSTED_PROXIES` set (`config :idejo, :trusted_proxies`, a list of
      `{address, prefix length}` parsed by `config/runtime.exs`): only peers in it;
    * unset: peers on a private network, as before AD-16. The bundled Caddy is one: in the
      Compose bundle the app is reachable only through it.

  From a trusted peer:

    * `X-Forwarded-For` gives `remote_ip`, which the rate limits count. Unset, its rightmost
      address (Caddy writes it, ignoring what the visitor sent); with a list, the rightmost
      address that is not itself a trusted proxy, so a chain of proxies works.
    * `X-Forwarded-Proto` gives `scheme`, read by `Plug.SSL` (plugged after this in the
      endpoint, so a visitor cannot claim https past it).
    * `X-Forwarded-Host` gives `host` (`IdejoWeb.ReturnBack` compares it with `Referer`).
      Links are never built from it: URLs come from `PHX_HOST` (the endpoint's `url`).

  From anyone else these headers are ignored. `config :idejo, :behind_proxy, false` trusts
  nobody.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if trusted?(conn.remote_ip) do
      conn |> forwarded_for() |> forwarded_proto() |> forwarded_host()
    else
      conn
    end
  end

  @doc """
  Whether `ip`, a request's peer, is a proxy whose forwarded headers are believed.
  """
  @spec trusted?(:inet.ip_address()) :: boolean()
  def trusted?(ip) do
    ip = unmap(ip)

    cond do
      not Application.get_env(:idejo, :behind_proxy, true) -> false
      proxies = Application.get_env(:idejo, :trusted_proxies) -> in_any?(ip, proxies)
      true -> private?(ip)
    end
  end

  defp forwarded_for(conn) do
    addresses =
      conn
      |> get_req_header("x-forwarded-for")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&parse/1)

    case client(addresses, Application.get_env(:idejo, :trusted_proxies)) do
      {:ok, ip} -> %{conn | remote_ip: ip}
      :error -> conn
    end
  end

  # Without a list: the rightmost address, as before AD-16.
  defp client([], _proxies), do: :error
  defp client(addresses, nil), do: List.last(addresses)

  # With one: from the right, past the trusted proxies of a chain.
  defp client(addresses, proxies) do
    addresses
    |> Enum.reverse()
    |> Enum.reduce_while(:error, fn
      {:ok, ip} = found, _acc ->
        if in_any?(unmap(ip), proxies), do: {:cont, found}, else: {:halt, found}

      :error, acc ->
        {:halt, acc}
    end)
  end

  defp parse(address) do
    case address |> String.trim() |> String.to_charlist() |> :inet.parse_strict_address() do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> :error
    end
  end

  defp forwarded_proto(conn) do
    case conn |> get_req_header("x-forwarded-proto") |> last_value() do
      "https" -> %{conn | scheme: :https, port: 443}
      "http" -> %{conn | scheme: :http, port: 80}
      _ -> conn
    end
  end

  # A host name, as a browser sends it: letters, digits, dots and dashes (no port, no path).
  defp forwarded_host(conn) do
    with host when is_binary(host) <- conn |> get_req_header("x-forwarded-host") |> last_value(),
         host = host |> String.split(":") |> hd() |> String.downcase(),
         true <- host =~ ~r/\A[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?\z/ do
      %{conn | host: host}
    else
      _ -> conn
    end
  end

  defp last_value([]), do: ""

  defp last_value(values),
    do: values |> Enum.join(",") |> String.split(",") |> List.last() |> String.trim()

  defp in_any?(ip, proxies), do: Enum.any?(proxies, &in_range?(ip, &1))

  defp in_range?(ip, {network, prefix}) when tuple_size(ip) == tuple_size(network) do
    <<head::bitstring-size(^prefix), _::bitstring>> = bits(ip)
    <<network_head::bitstring-size(^prefix), _::bitstring>> = bits(network)
    head == network_head
  end

  defp in_range?(_ip, _range), do: false

  defp bits({a, b, c, d}), do: <<a, b, c, d>>

  defp bits(ip) when tuple_size(ip) == 8,
    do: for(part <- Tuple.to_list(ip), into: <<>>, do: <<part::16>>)

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

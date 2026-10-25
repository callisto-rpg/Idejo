# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.Endpoint do
  @moduledoc """
  Whether the server may send to a push endpoint (PN-16). The address comes from the
  browser, so anyone signed in could name a machine on the server's own network; it is
  checked before a subscription is saved and again before each send:

    * `https` only, with a host and no user name or password in it;
    * the host is one of the push services allowed by the `push_services` setting (one per
      line; `*.example.com` allows any name ending in `.example.com`, not `example.com`
      itself);
    * every address the host resolves to is public: no loopback, private, link-local,
      shared (CGNAT), multicast, reserved or documentation range, IPv4 or IPv6 (mapped and
      NAT64 addresses are checked as the IPv4 address they carry).

  `check/1` returns the addresses, so the sender connects to one of them and DNS cannot
  answer differently in between. Names are resolved by `:inet.getaddrs/2`, or the
  `{module, function}` in `config :idejo, :push_resolver` (tests).

  Changes to this module get an extra careful human review (DV-06).
  """

  import Bitwise

  alias Idejo.Settings

  @type reason :: :invalid | :not_https | :not_allowed | :unresolvable | :private_address

  @doc "Checks `url`; returns its parsed URI and the public addresses its host resolves to."
  @spec check(String.t()) :: {:ok, URI.t(), [:inet.ip_address()]} | {:error, reason()}
  def check(url) when is_binary(url) do
    with {:ok, uri} <- parse(url),
         :ok <- allowed_host(uri.host),
         {:ok, addresses} <- resolve(uri.host),
         :ok <- public_addresses(addresses) do
      {:ok, uri, addresses}
    end
  end

  def check(_url), do: {:error, :invalid}

  defp parse(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host, userinfo: nil} = uri}
      when is_binary(host) and host != "" ->
        {:ok, %{uri | host: String.downcase(host)}}

      {:ok, %URI{scheme: "https"}} ->
        {:error, :invalid}

      {:ok, _uri} ->
        {:error, :not_https}

      {:error, _part} ->
        {:error, :invalid}
    end
  end

  @doc """
  Whether `host` matches the `push_services` allowlist: exactly, or under a `*.` pattern.
  """
  @spec allowed?(String.t()) :: boolean()
  def allowed?(host) do
    host = String.downcase(host)

    Enum.any?(patterns(), fn
      "*." <> domain -> String.ends_with?(host, "." <> domain)
      exact -> host == exact
    end)
  end

  defp allowed_host(host), do: if(allowed?(host), do: :ok, else: {:error, :not_allowed})

  @doc "The allowlist's patterns, lower case."
  @spec patterns() :: [String.t()]
  def patterns do
    :push_services
    |> Settings.get()
    |> String.split(["\n", "\r", ",", " "], trim: true)
    |> Enum.map(&String.downcase/1)
  end

  defp resolve(host) do
    {module, function} = Application.get_env(:idejo, :push_resolver, {__MODULE__, :getaddrs})

    case apply(module, function, [String.to_charlist(host)]) do
      [] -> {:error, :unresolvable}
      addresses when is_list(addresses) -> {:ok, addresses}
    end
  end

  @doc "Every IPv4 and IPv6 address of `host`, as `:inet` gives them."
  @spec getaddrs(charlist()) :: [:inet.ip_address()]
  def getaddrs(host) do
    Enum.flat_map([:inet, :inet6], fn family ->
      case :inet.getaddrs(host, family) do
        {:ok, addresses} -> addresses
        {:error, _} -> []
      end
    end)
  end

  defp public_addresses(addresses) do
    if Enum.all?(addresses, &public?/1), do: :ok, else: {:error, :private_address}
  end

  @doc "Whether an address may be sent to: not on a private, local or reserved network."
  @spec public?(:inet.ip_address()) :: boolean()
  def public?({a, b, c, d} = address)
      when a in 0..255 and b in 0..255 and c in 0..255 and d in 0..255,
      do: not Enum.any?(ipv4_blocks(), &in_block?(address, &1))

  # IPv4-mapped (::ffff:a.b.c.d), IPv4-compatible (::a.b.c.d) and NAT64 (64:ff9b::a.b.c.d)
  # addresses reach the IPv4 address they carry.
  def public?({0, 0, 0, 0, 0, 0xFFFF, x, y}), do: public?(ipv4(x, y))
  def public?({0x64, 0xFF9B, 0, 0, 0, 0, x, y}), do: public?(ipv4(x, y))

  def public?({0, 0, 0, 0, 0, 0, x, y}) when {x, y} not in [{0, 0}, {0, 1}],
    do: public?(ipv4(x, y))

  def public?({_, _, _, _, _, _, _, _} = address),
    do: not Enum.any?(ipv6_blocks(), &in_block?(address, &1))

  def public?(_address), do: false

  defp ipv4(x, y), do: {x >>> 8, x &&& 0xFF, y >>> 8, y &&& 0xFF}

  # RFC 6890 and the IANA special-purpose registries.
  defp ipv4_blocks do
    [
      {{0, 0, 0, 0}, 8},
      {{10, 0, 0, 0}, 8},
      {{100, 64, 0, 0}, 10},
      {{127, 0, 0, 0}, 8},
      {{169, 254, 0, 0}, 16},
      {{172, 16, 0, 0}, 12},
      {{192, 0, 0, 0}, 24},
      {{192, 0, 2, 0}, 24},
      {{192, 88, 99, 0}, 24},
      {{192, 168, 0, 0}, 16},
      {{198, 18, 0, 0}, 15},
      {{198, 51, 100, 0}, 24},
      {{203, 0, 113, 0}, 24},
      {{224, 0, 0, 0}, 4},
      {{240, 0, 0, 0}, 4}
    ]
  end

  defp ipv6_blocks do
    [
      {{0, 0, 0, 0, 0, 0, 0, 0}, 128},
      {{0, 0, 0, 0, 0, 0, 0, 1}, 128},
      {{0x0100, 0, 0, 0, 0, 0, 0, 0}, 64},
      {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 23},
      {{0x2001, 0x0DB8, 0, 0, 0, 0, 0, 0}, 32},
      {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16},
      {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
      {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
      {{0xFEC0, 0, 0, 0, 0, 0, 0, 0}, 10},
      {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
    ]
  end

  defp in_block?(address, {base, bits}) when tuple_size(address) == tuple_size(base) do
    width = if tuple_size(address) == 4, do: 8, else: 16
    shift = tuple_size(address) * width - bits
    to_integer(address, width) >>> shift == to_integer(base, width) >>> shift
  end

  defp in_block?(_address, _block), do: false

  defp to_integer(address, width),
    do: address |> Tuple.to_list() |> Enum.reduce(0, &(&2 <<< width ||| &1))
end

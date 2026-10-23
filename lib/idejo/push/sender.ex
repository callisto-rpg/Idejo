# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.Sender do
  @moduledoc """
  One push request to one browser's push service (PN-15, RFC 8030): the payload encrypted
  for that browser (`Idejo.Push.Crypto`), signed with the server's VAPID key, sent with a TTL
  and an urgency.

  The endpoint is checked again (PN-16) and the request goes to one of the addresses that
  check returned, with the host name kept for TLS (SNI and certificate) and the `Host`
  header, so a DNS answer that changes between the check and the connection cannot lead the
  request inside. Redirects are not followed.

  In tests, `config :idejo, :push_target` (a base URL such as `http://127.0.0.1:4010`)
  sends every request there instead, after the same checks: the fake push service.

  Changes to this module get an extra careful human review (DV-06).
  """

  alias Idejo.Push.{Crypto, Endpoint, Subscription, Vapid}

  @type result ::
          {:ok, pos_integer(), non_neg_integer() | nil}
          | {:error, {:endpoint, Endpoint.reason()} | {:vapid, atom()} | {:transport, term()}}

  @doc """
  Sends `payload` (a map, sent as JSON) to `subscription`. Returns the push service's status
  and its `Retry-After` in seconds (or nil), or why nothing was sent.

  Options: `:ttl` (seconds, required), `:urgency` (`"normal"` or `"high"`), `:contact`
  (the VAPID `sub`).
  """
  @spec deliver(Subscription.t(), map(), keyword()) :: result()
  def deliver(%Subscription{} = subscription, payload, opts) do
    with {:ok, uri, addresses} <- check(subscription.endpoint),
         {:ok, keys} <- vapid_keys() do
      {ua_public, auth} = Subscription.keys(subscription)
      body = payload |> Jason.encode!() |> Crypto.encrypt(ua_public, auth)

      headers = [
        {"ttl", Integer.to_string(Keyword.fetch!(opts, :ttl))},
        {"urgency", Keyword.get(opts, :urgency, "normal")},
        {"content-encoding", "aes128gcm"},
        {"content-type", "application/octet-stream"},
        {"authorization",
         Crypto.vapid_authorization(subscription.endpoint, keys, Keyword.fetch!(opts, :contact))}
      ]

      post(uri, addresses, headers, body)
    end
  end

  defp check(endpoint) do
    case Endpoint.check(endpoint) do
      {:ok, uri, addresses} -> {:ok, uri, addresses}
      {:error, reason} -> {:error, {:endpoint, reason}}
    end
  end

  defp vapid_keys do
    case Vapid.keys() do
      {:ok, keys} -> {:ok, keys}
      {:error, reason} -> {:error, {:vapid, reason}}
    end
  end

  defp post(uri, addresses, headers, body) do
    {own_headers, options} =
      uri
      |> request_options(addresses, Application.get_env(:idejo, :push_target))
      |> Keyword.pop!(:headers)

    case Req.post([headers: own_headers ++ headers, body: body] ++ options) do
      {:ok, %Req.Response{status: status} = response} ->
        {:ok, status,
         response |> Req.Response.get_header("retry-after") |> List.first() |> retry_after()}

      {:error, exception} ->
        {:error, {:transport, exception}}
    end
  end

  @doc """
  The Req options of a request to `uri` at one of `addresses` (IPv4 first): the address in
  the URL, the host name for TLS and in `Host`. With a `target` base URL (tests), that URL
  with the endpoint's path.
  """
  @spec request_options(URI.t(), [:inet.ip_address()], String.t() | nil) :: keyword()
  def request_options(uri, addresses, nil) do
    address = Enum.find(addresses, &(tuple_size(&1) == 4)) || hd(addresses)

    # URI.to_string/1 puts an IPv6 address in brackets.
    [
      url: URI.to_string(%{uri | host: to_string(:inet.ntoa(address))}),
      headers: [{"host", host_header(uri)}],
      connect_options: [hostname: uri.host, timeout: 10_000],
      receive_timeout: 15_000
    ] ++ common()
  end

  def request_options(uri, _addresses, target) when is_binary(target) do
    path = URI.to_string(%URI{path: uri.path, query: uri.query})
    [url: target <> path, headers: [{"x-push-host", uri.host}]] ++ common()
  end

  defp common, do: [retry: false, redirect: false, decode_body: false]

  defp host_header(%URI{host: host, port: 443}), do: host
  defp host_header(%URI{host: host, port: port}), do: "#{host}:#{port}"

  # Seconds, or an HTTP date (RFC 9110, section 10.2.3); at most a day, the TTL.
  defp retry_after(nil), do: nil

  defp retry_after(value) do
    seconds =
      case Integer.parse(String.trim(value)) do
        {seconds, ""} -> seconds
        _ -> date_seconds(value)
      end

    seconds && seconds |> max(0) |> min(86_400)
  end

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  # The IMF-fixdate form, "Sun, 06 Nov 1994 08:49:37 GMT", the one senders must use.
  defp date_seconds(value) do
    with [_, day, month, year, time] <-
           Regex.run(
             ~r/^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}:\d{2}:\d{2}) GMT$/,
             String.trim(value)
           ),
         month when is_integer(month) <- Enum.find_index(@months, &(&1 == month)),
         {:ok, date} <- Date.new(String.to_integer(year), month + 1, String.to_integer(day)),
         {:ok, time} <- Time.from_iso8601(time),
         {:ok, at} <- DateTime.new(date, time) do
      DateTime.diff(at, DateTime.utc_now())
    else
      _ -> nil
    end
  end
end

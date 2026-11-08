# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Plugins.Remote do
  @moduledoc """
  The plugins' requests to other servers (steward request, 2026-11-09: `forum`'s directory
  search and the chosen forum's logo). https only, to a host whose every address is public
  (`Idejo.Push.Endpoint.public?/1`, resolved as push endpoints are, `:push_resolver` in
  tests), connecting to the address checked (no DNS rebinding), no redirects, a few seconds
  and a size limit. Tests set `:plugins_req_options` (`Req.Test`).
  """

  alias Idejo.Push.Endpoint

  @doc "GET `url`: `{:ok, body}` for a 200 under `max_bytes`, else `:error`."
  @spec get(String.t(), keyword()) :: {:ok, term()} | :error
  def get(url, options \\ []) do
    {max_bytes, options} = Keyword.pop(options, :max_bytes, 512_000)

    with %URI{scheme: "https", host: host, userinfo: nil} = uri when is_binary(host) <-
           URI.parse(url),
         {:ok, addresses} <- addresses(host),
         {:ok, %{status: 200, body: body}} <- Req.get(request(uri, addresses, options)),
         true <- not is_binary(body) or byte_size(body) <= max_bytes do
      {:ok, body}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp addresses(host) do
    {module, function} = Application.get_env(:idejo, :push_resolver, {Endpoint, :getaddrs})

    case apply(module, function, [String.to_charlist(host)]) do
      [_ | _] = addresses ->
        if Enum.all?(addresses, &Endpoint.public?/1), do: {:ok, addresses}, else: :error

      _ ->
        :error
    end
  end

  # The checked address in the URL, the host name for TLS and in `Host`.
  defp request(uri, addresses, options) do
    address = Enum.find(addresses, &(tuple_size(&1) == 4)) || hd(addresses)
    host = if uri.port in [nil, 443], do: uri.host, else: "#{uri.host}:#{uri.port}"

    Req.new(
      url: URI.to_string(%{uri | host: to_string(:inet.ntoa(address))}),
      headers: [{"host", host}],
      connect_options: [hostname: uri.host, timeout: 2_000],
      receive_timeout: 3_000,
      retry: false,
      redirect: false
    )
    |> Req.merge(options)
    |> Req.merge(Application.get_env(:idejo, :plugins_req_options, []))
  end
end

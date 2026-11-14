# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.ContinueSignIn do
  @moduledoc """
  Signed in from one forum to the next (AC-09; steward request, 2026-11-14): links from the
  forums menu and the inbox to another forum of the group carry `sso=1` (`mark/1`). A
  visitor arriving with it, on a server signing in through the provider, is sent there
  silently (`GET /users/oidc?intent=continue`, `prompt=none`) and comes back to the page,
  signed in while the provider still knows them, else as a visitor, without a word. Signed
  in already, or without a provider, the page loads without the mark. GET only.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias Idejo.Accounts.OIDC

  @mark "sso"

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", query_params: %{@mark => _} = query} = conn, _opts) do
    path = clean(conn.request_path, Map.delete(query, @mark))
    signed_in? = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    if signed_in? || !OIDC.enabled?() do
      conn |> redirect(to: path) |> halt()
    else
      conn
      |> put_session(:user_return_to, path)
      |> redirect(to: "/users/oidc?intent=continue")
      |> halt()
    end
  end

  def call(conn, _opts), do: conn

  @doc "`url` (another forum's address) with the mark that signs its visitor in on arrival."
  @spec mark(String.t()) :: String.t()
  def mark(url) when is_binary(url) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "") |> Map.put(@mark, "1")
    URI.to_string(%{uri | query: URI.encode_query(query)})
  end

  defp clean(path, query) when map_size(query) == 0, do: path
  defp clean(path, query), do: path <> "?" <> URI.encode_query(query)
end

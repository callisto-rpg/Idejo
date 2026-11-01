# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ReturnBack do
  @moduledoc """
  Forms posted with `return=back` (the sidebar's × and +, the topic menu) lead back to the
  page they were sent from: the same-host `Referer`, as a local path, or nil.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @spec path(Plug.Conn.t(), map()) :: String.t() | nil
  def path(conn, %{"return" => "back"}) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: "/" <> _ = path} = uri when host == conn.host <-
           URI.parse(referer),
         false <- String.starts_with?(path, ["//", "/\\"]) do
      if uri.query, do: path <> "?" <> uri.query, else: path
    else
      _ -> nil
    end
  end

  def path(_conn, _params), do: nil
end

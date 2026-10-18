# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.RequireSetup do
  @moduledoc """
  Sends every browser page to the setup wizard while the server has no owner (AD-01).

  `/setup` itself and the development tools under `/dev` are let through. Tests turn the
  redirect off with `config :idejo, setup_redirect: false` unless they test it.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: [first | _]} = conn, _opts) when first in ["setup", "dev"],
    do: conn

  def call(conn, _opts) do
    if Application.get_env(:idejo, :setup_redirect, true) and Idejo.Setup.needed?() do
      conn |> redirect(to: "/setup") |> halt()
    else
      conn
    end
  end
end

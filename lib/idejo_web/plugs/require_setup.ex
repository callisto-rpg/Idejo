# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.RequireSetup do
  @moduledoc """
  Sends every browser page to the setup wizard while the server has no owner (AD-01).

  `/setup` itself and the development tools under `/dev` are let through. Tests turn the
  redirect off with `config :idejo, setup_redirect: false` unless they test it.

  Once an owner exists the wizard is gone for good (owners cannot all be removed, and a
  backup is restored with the server stopped), so after the first page that finds one no
  page asks the database again until the server restarts.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @set_up {__MODULE__, :set_up}

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: [first | _]} = conn, _opts) when first in ["setup", "dev"],
    do: conn

  def call(conn, _opts) do
    if Application.get_env(:idejo, :setup_redirect, true) and setup_needed?() do
      conn |> redirect(to: "/setup") |> halt()
    else
      conn
    end
  end

  defp setup_needed? do
    if :persistent_term.get(@set_up, false) do
      false
    else
      needed? = Idejo.Setup.needed?()
      if not needed?, do: :persistent_term.put(@set_up, true)
      needed?
    end
  end

  @doc "Forgets that the server was found set up: for tests that start from an empty server."
  @spec forget() :: :ok
  def forget do
    :persistent_term.erase(@set_up)
    :ok
  end
end

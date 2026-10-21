# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      IdejoWeb.Telemetry,
      Idejo.Repo,
      {DNSCluster, query: Application.get_env(:idejo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Idejo.PubSub},
      # Growing messages: one timer process per open message (GM-03), rebuilt at boot.
      {Registry, keys: :unique, name: Idejo.Messages.Registry},
      {DynamicSupervisor, name: Idejo.Messages.OpenMessageSupervisor, strategy: :one_for_one},
      # Closes an open message once its author has been gone for the grace (GM-12).
      Idejo.Messages.Authors,
      # SP-05: rate limit counters, in memory.
      {Idejo.RateLimit, clean_period: :timer.minutes(10)},
      if(Application.get_env(:idejo, :recover_open_messages, true),
        do: Idejo.Messages.Recovery
      ),
      # Writes the setup link to the log while the server has no owner (AD-01).
      if(Application.get_env(:idejo, :announce_setup, true), do: Idejo.Setup.Announcer),
      # Start to serve requests, typically the last entry
      IdejoWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Idejo.Supervisor]
    Supervisor.start_link(Enum.reject(children, &is_nil/1), opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    IdejoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

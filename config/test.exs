# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

import Config

# Only in tests, lower the Argon2id cost so the suite stays fast
config :argon2_elixir, t_cost: 1, m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :idejo, Idejo.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "idejo_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :idejo, IdejoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "yyw4cb3Wq4k4Te003uYd5OEFKzj9XkQOKrF0fGYJcKkB4RWnHTdbzlabfAdJLaD5",
  server: false

# In test we don't send emails
config :idejo, Idejo.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# AD-01: no setup link in the test log, and pages are not sent to the wizard unless a test
# asks for it.
config :idejo, announce_setup: false, setup_redirect: false

# Tests run Idejo.Messages.Recovery themselves, inside the SQL sandbox.
config :idejo, recover_open_messages: false

# SP-05: no rate limits in the suite (thousands of requests from 127.0.0.1); the rate limit
# tests turn them on.
config :idejo, :rate_limits, enabled: false

# PN-16: push endpoints resolve to fixed addresses, with no network.
config :idejo, :push_resolver, {Idejo.FakeDNS, :getaddrs}

# TP-12: uploads go to a scratch directory, emptied by test_helper.exs.
config :idejo, :uploads_dir, Path.expand("../tmp/test_uploads", __DIR__)
config :idejo, :backup_dir, Path.expand("../tmp/test_backups", __DIR__)

# Jobs run only when a test runs them (Oban.Testing).
config :idejo, Oban, testing: :manual

# Views end with each test; their disconnect grace (GM-12) must not fire during the run.
# Tests that need one pass `grace_ms:` to Idejo.Messages.Authors.
config :idejo, gm_disconnect_grace_ms: :timer.hours(1)

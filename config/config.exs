# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :idejo, :scopes,
  user: [
    default: true,
    module: Idejo.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Idejo.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :idejo,
  ecto_repos: [Idejo.Repo],
  generators: [timestamp_type: :utc_datetime]

# Base of every stable URI (FD-01). Set from PHX_HOST in production; never change it
# once a server has content, since URIs are stored at creation.
config :idejo, :base_uri, "http://localhost:4000"

# TP-12: where uploaded images are stored on local disk (production: IDEJO_UPLOADS_DIR, the
# Compose volume /data/uploads by default).
config :idejo, :uploads_dir, Path.expand("../tmp/uploads", __DIR__)

# AD-05: nightly backups (database and uploads) on local disk, the newest 7 kept. Backups are
# Oban jobs; the cron runs in UTC.
config :idejo, :backup_dir, Path.expand("../tmp/backups", __DIR__)

config :idejo, Oban,
  repo: Idejo.Repo,
  queues: [maintenance: 1, messages: 5, push: 10],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Idejo.Backup.Worker},
       {"0 4 * * *", Idejo.Uploads.CleanupWorker},
       # The email summaries (steward decision, 2026-10-23).
       {"0 * * * *", Idejo.Notifications.DigestWorker}
     ]}
  ]

# SP-02: passwords are hashed with Argon2id at a pinned cost (3 passes, 2^16 KiB = 64 MiB,
# 4 lanes), so a dependency update cannot silently weaken it. Tests lower the cost.
config :argon2_elixir, argon2_type: 2, t_cost: 3, m_cost: 16, parallelism: 4

# SP-02: session and remember-me cookies carry the Secure flag. Only dev turns it off,
# since it serves plain http.
config :idejo, :secure_cookies, true

# LI-03: the upstream repository; the footer links to it at the commit the release was built
# from. A server running modified code sets IDEJO_SOURCE_URL instead (see config/runtime.exs).
config :idejo, :upstream_source_url, "https://github.com/callisto-rpg/Idejo"

# Configure the endpoint
config :idejo, IdejoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: IdejoWeb.ErrorHTML, json: IdejoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Idejo.PubSub,
  live_view: [signing_salt: "3HFHXU8y"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :idejo, Idejo.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  idejo: [
    args:
      ~w(js/app.js js/theme.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  idejo: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

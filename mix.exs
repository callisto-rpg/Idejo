# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.MixProject do
  use Mix.Project

  def project do
    [
      app: :idejo,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [plt_local_path: "priv/plts"],
      releases: [idejo: [steps: [:assemble, &copy_licence/1]]]
    ]
  end

  @licence_files ~w(LICENSE NOTICE LICENSES)

  # LI-01: the licence text and the NOTICE ship with every install, at the release's root.
  @doc false
  def copy_licence(%Mix.Release{path: path} = release) do
    for file <- @licence_files, do: File.cp_r!(file, Path.join(path, file))
    release
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Idejo.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.15"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      # SMTP delivery for Swoosh (AD-08). BSD-2-Clause; its dependency ranch is ISC (LI-06).
      {:gen_smtp, "~> 1.3"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:oban, "~> 2.24"},
      {:argon2_elixir, "~> 4.1"},
      # Markdown source to sanitised HTML (FD-03). MIT; rustler_precompiled Apache-2.0 (LI-06).
      {:mdex, "~> 0.14.2"},
      # Images (TP-12): libvips through Vix, to re-encode uploads and strip their metadata
      # (SP-05). Apache-2.0 (image), MIT (vix); libvips itself is LGPL, steward-approved.
      {:image, "~> 0.72.0"},
      # Rate limits on every endpoint (SP-05), in memory (ETS). MIT (LI-06).
      {:hammer, "~> 7.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.16.0", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind idejo", "esbuild idejo"],
      "assets.deploy": [
        "tailwind idejo --minify",
        "esbuild idejo --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "sobelow --config --exit",
        "deps.audit",
        "cmd mix hex.audit",
        "test --warnings-as-errors",
        # As CI runs it (dev env, without test/support), so precommit catches what CI would.
        "cmd env MIX_ENV=dev mix dialyzer"
      ]
    ]
  end
end

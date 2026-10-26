# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.RepositoryTest do
  @moduledoc """
  Requirements met by the repository itself: its configuration, build and process files.
  """
  use ExUnit.Case, async: true

  alias Idejo.Requirements
  alias Mix.Dep.Lock

  defp read(path), do: File.read!(path)

  defp tracked_files do
    {out, 0} = System.cmd("git", ["ls-files"])
    out |> String.split("\n", trim: true) |> Enum.filter(&File.regular?/1)
  end

  @tag req: "SP-01"
  test "SP-01 HTTPS only: TLS 1.2 or later, automatic certificates, HSTS and secure cookies" do
    caddy = read("deploy/Caddyfile")
    # A site named by its domain gets certificates from Let's Encrypt, renewed by Caddy.
    assert caddy =~ ~r/^\{\$IDEJO_DOMAIN\} \{/m
    assert caddy =~ "email {$ACME_EMAIL}"
    assert caddy =~ "protocols tls1.2 tls1.3"
    assert caddy =~ ~s(Strict-Transport-Security "max-age=31536000)

    prod = Config.Reader.read!("config/prod.exs", env: :prod)
    force_ssl = prod[:idejo][IdejoWeb.Endpoint][:force_ssl]
    assert force_ssl[:rewrite_on] == [:x_forwarded_proto]
    # Plug.SSL sends HSTS unless told not to.
    refute Keyword.get(force_ssl, :hsts) == false

    base = Config.Reader.read!("config/config.exs", env: :prod)
    assert base[:idejo][:secure_cookies] == true
    refute Keyword.has_key?(prod[:idejo], :secure_cookies)
  end

  # Split, so REUSE does not take these strings for this file's own header.
  @copyright "SPDX-" <> "FileCopyrightText: 2026 Mariano Pictet and contributors"
  @licence "SPDX-" <> "License-Identifier: AGPL-3.0-only"

  @tag req: "LI-01"
  test "LI-01 every source file carries the SPDX header" do
    sources =
      Enum.filter(tracked_files(), fn path ->
        Path.extname(path) in ~w(.ex .exs .heex .js .css .yml .yaml .sh .bat .toml) or
          Path.basename(path) in ~w(Dockerfile Caddyfile .dockerignore) or
          String.starts_with?(path, "rel/overlays/bin/")
      end)
      # Third-party and generated files are covered by REUSE.toml (reuse lint checks those).
      |> Enum.reject(&String.starts_with?(&1, ["assets/vendor/", "priv/static/"]))

    assert length(sources) > 100

    without =
      for path <- sources,
          path != "REUSE.toml",
          head = path |> File.read!() |> String.slice(0, 600),
          not (head =~ @copyright and head =~ @licence),
          do: path

    assert without == []
  end

  @tag req: "LI-01", tmp_dir: true
  test "LI-01 the licence text ships in the repository and with every install", %{
    tmp_dir: tmp_dir
  } do
    assert read("LICENSES/AGPL-3.0-only.txt") =~ "GNU AFFERO GENERAL PUBLIC LICENSE"
    assert read("LICENSE") =~ "GNU AFFERO GENERAL PUBLIC LICENSE"

    # The release step copies them to the root of the release (the Docker image's /app).
    Idejo.MixProject.copy_licence(%Mix.Release{path: tmp_dir})
    assert File.read!(Path.join(tmp_dir, "LICENSES/AGPL-3.0-only.txt")) =~ "AFFERO"
    assert File.read!(Path.join(tmp_dir, "NOTICE")) == read("NOTICE")
    assert File.exists?(Path.join(tmp_dir, "LICENSE"))

    dockerfile = read("Dockerfile")
    assert dockerfile =~ "COPY LICENSE NOTICE ./"
    assert dockerfile =~ "COPY LICENSES LICENSES"
  end

  @tag req: "LI-05"
  test "LI-05 the CLA check links the individual and corporate CLA and its sign sentence" do
    cla = read("docs/legal/CLA.md")
    assert cla =~ "Part A — Individual Contributor Licence Agreement"
    assert cla =~ "Part B — Corporate Contributor Licence Agreement"
    assert cla =~ "Right to relicense"

    # The sentence the CLA asks for is the one the workflow accepts.
    workflow = read(".github/workflows/cla.yml")
    assert workflow =~ "/blob/main/docs/legal/CLA.md"
    [sentence] = Regex.run(~r/body == '(I have read [^']+)'/, workflow, capture: :all_but_first)
    assert cla =~ "> " <> sentence
  end

  @tag req: "DV-01"
  test "DV-01 CLAUDE.md describes architecture, conventions, commands and the requirement IDs" do
    claude = read("CLAUDE.md")

    for section <- ["## Architecture", "## Conventions", "## Commands", "## Milestones"] do
      assert claude =~ section
    end

    prefixes = Requirements.mvp() |> Enum.map(&String.slice(&1, 0, 2)) |> Enum.uniq()
    for prefix <- prefixes, do: assert(claude =~ ~r/\b#{prefix}-\d{2}\b/, prefix)
  end

  @tag req: "DV-03"
  test "DV-03 formatter, linter, type checks, tests and accessibility checks run everywhere" do
    precommit = Mix.Project.config()[:aliases][:precommit]
    ci = read(".github/workflows/ci.yml")

    for {step, ci_step} <- [
          {"format", "mix format --check-formatted"},
          {"credo --strict", "mix credo --strict"},
          {"cmd env MIX_ENV=dev mix dialyzer", "mix dialyzer"},
          {"test --warnings-as-errors", "mix test --warnings-as-errors"}
        ] do
      assert step in precommit
      assert ci =~ ci_step
    end

    # The accessibility checks are tests (AX-01), so they run wherever the tests do.
    assert read("test/idejo_web/accessibility_test.exs") =~ ~s(@tag req: "AX-01")
  end

  @tag req: "DV-04"
  test "DV-04 Erlang, Elixir and every dependency are pinned, the same everywhere" do
    versions =
      for line <- String.split(read(".tool-versions"), "\n", trim: true), into: %{} do
        [tool, version] = String.split(line)
        {tool, version}
      end

    assert versions["erlang"] =~ ~r/\A\d+\.\d+(\.\d+)*\z/
    assert versions["elixir"] =~ ~r/\A\d+\.\d+\.\d+-otp-\d+\z/
    assert read(".github/workflows/ci.yml") =~ "version-file: .tool-versions"

    # The Docker image builds with the same versions.
    dockerfile = read("Dockerfile")
    [elixir, _otp] = String.split(versions["elixir"], "-otp-")
    assert dockerfile =~ "ARG ELIXIR_VERSION=#{elixir}\n"
    assert dockerfile =~ "ARG OTP_VERSION=#{versions["erlang"]}\n"

    # mix.lock holds the exact version of every dependency.
    lock = Lock.read()

    for dep <- Mix.Project.config()[:deps], app = elem(dep, 0) do
      assert Map.has_key?(lock, app), "#{app} is not in mix.lock"
    end
  end

  @tag req: "DV-04"
  test "DV-04 the full stack starts with one Docker Compose command" do
    compose = read("deploy/docker-compose.yml")

    for service <- ["app:", "db:", "caddy:"], do: assert(compose =~ "\n  #{service}\n")
    assert compose =~ "dockerfile: Dockerfile"
    assert read("CLAUDE.md") =~ "deploy/docker-compose.yml"
  end

  @tag req: "DV-06"
  test "DV-06 dependencies are audited on every build, and sensitive changes flagged" do
    precommit = Mix.Project.config()[:aliases][:precommit]
    assert "deps.audit" in precommit
    assert "cmd mix hex.audit" in precommit

    ci = read(".github/workflows/ci.yml")
    assert ci =~ "mix deps.audit"
    assert ci =~ "mix hex.audit"

    assert read(".github/pull_request_template.md") =~
             "Touches auth, permissions, uploads or security plugs"
  end
end

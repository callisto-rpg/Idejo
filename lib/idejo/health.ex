# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Health do
  @moduledoc """
  The health report of `GET /health` (AD-15): the app's version and whether the database
  answers and every migration of this release is applied. Plain words only: no error text,
  no names, no counts, so it can be served to anyone (`Idejo.Release.health/0`, for the
  operator at the command line, says more).
  """

  alias Idejo.Repo

  @timeout 2_000

  @type report :: %{
          status: String.t(),
          version: String.t(),
          checks: %{database: String.t(), migrations: String.t()}
        }

  @doc """
  The report. `opts` (for tests): `:repo`, the repository to check, and
  `:migrations_path`, where the release's migrations are.
  """
  @spec report(keyword()) :: report()
  def report(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    database = database(repo)

    # Without a database, the migrations cannot be read.
    migrations =
      if database == "ok", do: migrations(repo, opts[:migrations_path]), else: "error"

    %{
      status: if(database == "ok" and migrations == "ok", do: "ok", else: "error"),
      version: version(),
      checks: %{database: database, migrations: migrations}
    }
  end

  @doc "The app's version, from its `mix.exs`."
  @spec version() :: String.t()
  def version, do: :idejo |> Application.spec(:vsn) |> to_string()

  @doc """
  `"ok"` when the database answers a trivial query within #{@timeout} ms, else `"error"`.
  """
  @spec database(module()) :: String.t()
  def database(repo \\ Repo) do
    case repo.query("SELECT 1", [], timeout: @timeout) do
      {:ok, _} -> "ok"
      {:error, _} -> "error"
    end
  rescue
    _ -> "error"
  catch
    :exit, _ -> "error"
  end

  @doc """
  `"ok"` when every migration of this release is applied, `"pending"` when one is not,
  `"error"` when they cannot be read.
  """
  @spec migrations(module(), String.t() | nil) :: String.t()
  def migrations(repo \\ Repo, path \\ nil) do
    path = path || Ecto.Migrator.migrations_path(repo)

    if Enum.any?(Ecto.Migrator.migrations(repo, path), &match?({:down, _, _}, &1)),
      do: "pending",
      else: "ok"
  rescue
    _ -> "error"
  catch
    :exit, _ -> "error"
  end
end

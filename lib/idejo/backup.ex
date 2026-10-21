# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Backup do
  @moduledoc """
  Backups of the database and the uploaded files (AD-05), in one file on local disk.

  A backup is a tar archive named `idejo-YYYYMMDD-HHMMSS.tar` (UTC) in the `:backup_dir`
  directory, holding:

    * `manifest.json` - the format, the time, and the last migration of the database;
    * `database.dump` - `pg_dump` in its custom format;
    * `uploads/<name>` - every uploaded file.

  `Idejo.Backup.Worker` makes one every night at 03:00 UTC and keeps the newest 7.
  `bin/idejo-admin backup` makes one at once, and `bin/idejo-admin restore FILE` puts one
  back (AD-09, `Idejo.Release`).

  `pg_dump` and `pg_restore` must match the server's major version: the Docker image
  installs them, `:pg_bin_dir` (`IDEJO_PG_BIN_DIR`) points elsewhere.
  """

  require Logger

  alias Ecto.Adapters.SQL
  alias Idejo.Audit
  alias Idejo.Repo

  @keep 7
  @format 1
  @name ~r/\Aidejo-\d{8}-\d{6}(-\d+)?\.tar\z/

  @type info :: %{name: String.t(), path: Path.t(), size: non_neg_integer()}

  @doc "How many backups are kept."
  @spec keep() :: pos_integer()
  def keep, do: @keep

  @doc "The directory backups are written to."
  @spec dir() :: Path.t()
  def dir, do: Application.fetch_env!(:idejo, :backup_dir)

  ## Making a backup

  @doc """
  Makes a backup: the database first, then the uploads, so every file the dumped database
  names is in the archive. Written under a temporary name and renamed when complete, so a
  backup that is listed is whole. Returns its path.
  """
  @spec create() :: {:ok, Path.t()} | {:error, String.t()}
  def create do
    dir = dir()
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")

    case mkdir(dir) do
      :ok -> write_backup(free_path(dir, "idejo-#{stamp}"))
      {:error, reason} -> {:error, describe(reason)}
    end
  end

  # Paths in this module are the configured directories, names made here, names from a
  # listing of those directories, or a backup named by the operator on the command line.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_backup(path) do
    tmp = path <> ".tmp"
    dump = path <> ".dump"

    result =
      with :ok <- pg_dump(dump),
           :ok <- write_archive(tmp, dump),
           do: File.rename(tmp, path)

    File.rm(dump)
    File.rm(tmp)

    case result do
      :ok ->
        Logger.info("Backup written to #{path}")
        {:ok, path}

      {:error, reason} ->
        {:error, describe(reason)}
    end
  end

  # Two backups in the same second get "-2", "-3"…
  defp free_path(dir, base, n \\ 1) do
    name = if n == 1, do: "#{base}.tar", else: "#{base}-#{n}.tar"
    path = Path.join(dir, name)
    if File.exists?(path), do: free_path(dir, base, n + 1), else: path
  end

  defp write_archive(tmp, dump) do
    manifest = %{
      "format" => @format,
      "created_at" => DateTime.utc_now(),
      "migration" => last_migration()
    }

    with {:ok, tar} <- :erl_tar.open(String.to_charlist(tmp), [:write]) do
      try do
        :ok = :erl_tar.add(tar, Jason.encode!(manifest), ~c"manifest.json", [])
        :ok = :erl_tar.add(tar, String.to_charlist(dump), ~c"database.dump", [])

        for name <- upload_names() do
          path = String.to_charlist(Path.join(uploads_dir(), name))
          :ok = :erl_tar.add(tar, path, String.to_charlist("uploads/" <> name), [])
        end

        :ok
      after
        :erl_tar.close(tar)
      end
    end
  end

  # Regular files only: not the health check's probe or a restore's staging directory.
  defp upload_names do
    dir = uploads_dir()

    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.filter(&File.regular?(Path.join(dir, &1)))
        |> Enum.sort()

      {:error, :enoent} ->
        []
    end
  end

  ## Listing and pruning

  @doc "The backups in `dir/0`, newest first."
  @spec list() :: [info()]
  def list do
    dir = dir()

    case File.ls(dir) do
      {:ok, names} ->
        for name <- names,
            Regex.match?(@name, name),
            {:ok, stat} = File.stat(Path.join(dir, name)) do
          %{name: name, path: Path.join(dir, name), size: stat.size}
        end
        |> Enum.sort_by(&sort_key(&1.name), :desc)

      {:error, _} ->
        []
    end
  end

  # "idejo-20261021-030000.tar" < "idejo-20261021-030000-2.tar".
  defp sort_key(name) do
    case Regex.run(~r/\Aidejo-(\d{8}-\d{6})(?:-(\d+))?\.tar\z/, name) do
      [_, stamp, n] -> {stamp, String.to_integer(n)}
      [_, stamp] -> {stamp, 1}
    end
  end

  @doc "Deletes all but the newest `keep/0` backups. Returns the names deleted."
  @spec prune() :: [String.t()]
  # sobelow_skip ["Traversal.FileModule"]
  def prune do
    for %{name: name, path: path} <- Enum.drop(list(), @keep) do
      File.rm!(path)
      name
    end
  end

  ## Restoring

  @doc """
  Puts a backup back: the database and the uploads are replaced by the backup's. The server
  must be stopped (`bin/idejo-admin restore` checks it).

  First makes a backup of what is there now, so a wrong restore can be undone. Then empties
  the database, restores the dump, runs the migrations a backup from an older version lacks,
  replaces the uploaded files and records `backup.restore` in the audit log. Refuses a
  backup made by a newer version of Idejo.

  Returns the path of the backup made first.
  """
  @spec restore(Path.t()) :: {:ok, Path.t()} | {:error, String.t()}
  # sobelow_skip ["Traversal.FileModule"]
  def restore(path) do
    with {:ok, manifest} <- read_manifest(path),
         :ok <- check_version(manifest),
         {:ok, before} <- create(),
         staging = Path.join(uploads_dir(), ".restore"),
         :ok <- extract(path, staging),
         :ok <- restore_database(Path.join(staging, "database.dump")),
         :ok <- replace_uploads(Path.join(staging, "uploads")),
         {:ok, _} <-
           Audit.record(nil, "backup.restore", nil, %{"backup" => Path.basename(path)}) do
      File.rm_rf(staging)
      Logger.info("Backup #{path} restored")
      {:ok, before}
    else
      {:error, reason} ->
        File.rm_rf(Path.join(uploads_dir(), ".restore"))
        {:error, describe(reason)}
    end
  end

  # Only these names may come out of an archive: nothing outside the staging directory.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_manifest(path) do
    with true <- File.regular?(path) || {:error, :no_such_backup},
         {:ok, names} <- :erl_tar.table(String.to_charlist(path)),
         true <- Enum.all?(names, &allowed_name?(to_string(&1))) || {:error, :not_a_backup},
         {:ok, [{_, json}]} <-
           :erl_tar.extract(String.to_charlist(path), [:memory, files: [~c"manifest.json"]]),
         {:ok, %{"format" => @format} = manifest} <- Jason.decode(json) do
      {:ok, manifest}
    else
      {:error, :no_such_backup} -> {:error, :no_such_backup}
      _ -> {:error, :not_a_backup}
    end
  end

  defp allowed_name?(name) when name in ["manifest.json", "database.dump"], do: true

  defp allowed_name?("uploads/" <> file),
    do: file != "" and not String.contains?(file, "/") and not String.starts_with?(file, ".")

  defp allowed_name?(_), do: false

  # The backup's last migration must be one this version knows.
  defp check_version(%{"migration" => migration}) do
    known =
      for file <- Path.wildcard(Path.join(Ecto.Migrator.migrations_path(Repo), "*.exs")),
          [digits] <- [Regex.run(~r/\A\d+/, Path.basename(file))],
          do: String.to_integer(digits)

    if migration in known, do: :ok, else: {:error, :newer_version}
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp extract(path, staging) do
    File.rm_rf!(staging)

    with :ok <- File.mkdir_p(staging),
         :ok <- :erl_tar.extract(String.to_charlist(path), [{:cwd, String.to_charlist(staging)}]) do
      File.mkdir_p(Path.join(staging, "uploads"))
    end
  end

  # The dump recreates every table; tables of a newer schema would otherwise stay behind.
  defp restore_database(dump) do
    Repo.query!("DROP SCHEMA public CASCADE")
    Repo.query!("CREATE SCHEMA public")

    with :ok <-
           pg(:pg_restore, [
             "--no-owner",
             "--no-privileges",
             "--exit-on-error",
             "--single-transaction",
             "--dbname",
             db_config()[:database],
             dump
           ]) do
      # Statements prepared before name the dropped tables and types: drop the pool's
      # connections as they are next used. The server starts afresh after a restore anyway.
      SQL.disconnect_all(Repo.get_dynamic_repo(), 0)
      Ecto.Migrator.run(Repo, :up, all: true, log: false, dynamic_repo: Repo.get_dynamic_repo())
      :ok
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp replace_uploads(from) do
    dir = uploads_dir()
    Enum.each(upload_names(), &File.rm!(Path.join(dir, &1)))

    from
    |> File.ls!()
    |> Enum.each(&File.rename!(Path.join(from, &1), Path.join(dir, &1)))
  end

  ## PostgreSQL tools

  defp pg_dump(file) do
    pg(:pg_dump, ["--format", "custom", "--file", file, db_config()[:database]])
  end

  # No shell: the tool is pg_dump or pg_restore from the configuration or the PATH, and the
  # arguments are a list.
  # sobelow_skip ["CI.System"]
  defp pg(tool, args) do
    config = db_config()
    exe = executable(tool)

    connection =
      Enum.flat_map([host: :hostname, port: :port, username: :username], fn {flag, key} ->
        if value = config[key], do: ["--#{flag}", to_string(value)], else: []
      end)

    env = if password = config[:password], do: [{"PGPASSWORD", password}], else: []

    if exe do
      case System.cmd(exe, connection ++ args, env: env, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, _} -> {:error, {tool, String.trim(output)}}
      end
    else
      {:error, {:missing, tool}}
    end
  end

  defp executable(tool) do
    case Application.get_env(:idejo, :pg_bin_dir) do
      nil -> System.find_executable(to_string(tool))
      bin -> Path.join(bin, to_string(tool))
    end
  end

  # The repo's configuration with its URL taken apart (DATABASE_URL in production).
  defp db_config do
    config = Repo.config()

    case config[:url] do
      nil -> config
      url -> Keyword.merge(config, Ecto.Repo.Supervisor.parse_url(url))
    end
  end

  defp last_migration do
    Repo.query!("SELECT max(version) FROM schema_migrations").rows |> hd() |> hd()
  end

  defp uploads_dir, do: Application.fetch_env!(:idejo, :uploads_dir)

  # sobelow_skip ["Traversal.FileModule"]
  defp mkdir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:dir, dir, reason}}
    end
  end

  defp describe({:dir, dir, reason}),
    do: "cannot write to #{dir}: #{:file.format_error(reason)}"

  defp describe({:missing, tool}),
    do: "#{tool} not found; install the PostgreSQL client matching the server's version"

  defp describe({tool, output}) when tool in [:pg_dump, :pg_restore], do: "#{tool}: #{output}"
  defp describe(:no_such_backup), do: "no such file"
  defp describe(:not_a_backup), do: "not an Idejo backup"
  defp describe(:newer_version), do: "made by a newer version of Idejo; upgrade it first"
  defp describe(reason) when is_atom(reason), do: :file.format_error(reason) |> to_string()
  defp describe(reason), do: inspect(reason)
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Release do
  @moduledoc """
  Tasks run from the command line of a release, without Mix: migrations, and the recovery
  commands of `bin/idejo-admin` (AD-09).

  The recovery commands work whether the server is running or not. `bin/idejo-admin` runs
  them inside the running server (`bin/idejo rpc`) when there is one, so ended sessions are
  disconnected at once, and in a fresh VM (`bin/idejo eval`) otherwise, starting only the
  repo. They print what happened and fail with a non-zero exit status, never by halting the
  VM, which under `rpc` is the server's.
  """
  @app :idejo

  import Ecto.Query, warn: false
  alias Idejo.Access.{Role, UserRole}
  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Backup
  alias Idejo.Push.Vapid
  alias Idejo.Repo

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  ## Owner password (AD-09)

  @doc """
  `bin/idejo-admin reset-owner-password [USERNAME]`: gives an owner a new random password,
  printed once, and ends all their sessions. `username` may be left out when the server has
  one owner.
  """
  @spec reset_owner_password(String.t() | nil) :: :ok
  def reset_owner_password(username \\ nil) do
    case with_repo(fn -> reset_owner_password!(blank_to_nil(username)) end) do
      {:ok, {user, password}} ->
        IO.puts("""
        New password for #{user.username} (#{user.email}):

            #{password}

        All their sessions have ended. Sign in with it, then change it in your profile.\
        """)

      {:error, reason} ->
        fail(reset_error(reason))
    end
  end

  @doc """
  Sets a new random password for an owner, ends their sessions and records
  `user.password_reset` in the audit log, with no admin (the command line). Returns the
  owner and the password.
  """
  @spec reset_owner_password!(String.t() | nil) ::
          {:ok, {User.t(), String.t()}}
          | {:error, :no_owner | :not_an_owner | {:several_owners, [String.t()]}}
  def reset_owner_password!(username) do
    password = :crypto.strong_rand_bytes(18) |> Base.url_encode64()

    result =
      Repo.transact(fn ->
        with {:ok, owner} <- find_owner(username),
             {:ok, {owner, socket_ids}} <-
               Accounts.reset_user_password(owner, %{password: password}),
             {:ok, _} <-
               Audit.record(nil, "user.password_reset", nil, %{"user" => owner.username}) do
          {:ok, {owner, socket_ids}}
        end
      end)

    with {:ok, {owner, socket_ids}} <- result do
      # Only inside the running server (rpc); a fresh VM has no LiveViews to disconnect.
      if Process.whereis(IdejoWeb.Endpoint), do: IdejoWeb.UserAuth.disconnect_sessions(socket_ids)
      {:ok, {owner, password}}
    end
  end

  defp find_owner(nil) do
    case Repo.all(owners_query()) do
      [] -> {:error, :no_owner}
      [owner] -> {:ok, owner}
      owners -> {:error, {:several_owners, Enum.map(owners, & &1.username)}}
    end
  end

  defp find_owner(username) do
    case Repo.one(from u in owners_query(), where: u.username == ^username) do
      nil -> {:error, :not_an_owner}
      owner -> {:ok, owner}
    end
  end

  defp owners_query do
    from u in User,
      join: ur in UserRole,
      on: ur.user_id == u.id,
      join: r in Role,
      on: r.id == ur.role_id,
      where: r.built_in and r.name == "owner",
      order_by: u.username
  end

  defp reset_error(:no_owner),
    do: "This server has no owner yet. Open it in a browser to run the setup wizard."

  defp reset_error(:not_an_owner), do: "No owner has that username."

  defp reset_error({:several_owners, usernames}),
    do: "This server has several owners; name one: #{Enum.join(usernames, ", ")}"

  ## Backup and restore (AD-05, AD-09)

  @doc """
  `bin/idejo-admin backup`: makes a backup now, like the nightly one, and keeps the newest
  `Idejo.Backup.keep/0`.
  """
  @spec backup() :: :ok
  def backup do
    case with_repo(&Backup.create/0) do
      {:ok, path} ->
        IO.puts("Backup written to #{path}")
        for name <- Backup.prune(), do: IO.puts("Old backup #{name} deleted")
        :ok

      {:error, reason} ->
        fail("Backup failed: #{reason}")
    end
  end

  @doc """
  `bin/idejo-admin restore FILE`: replaces the database and the uploads with a backup's,
  after backing up what is there now. Only while the server is stopped. A bare file name is
  looked for in the backup directory; `bin/idejo-admin` makes other paths absolute.
  """
  @spec restore(String.t()) :: :ok
  def restore(file) do
    if Process.whereis(IdejoWeb.Endpoint), do: fail("Stop the server before restoring.")
    path = if Path.basename(file) == file, do: Path.join(Backup.dir(), file), else: file

    case with_repo(fn -> Backup.restore(path) end) do
      {:ok, before} ->
        IO.puts("""
        Restored #{path}.
        What was there before is in #{before}.\
        """)

      {:error, reason} ->
        fail("Restore failed: #{reason}")
    end
  end

  ## Push keys (PN-14, AD-09)

  @doc """
  `bin/idejo-admin push-key`: prints the server's VAPID public key, the one browsers
  subscribe with.
  """
  @spec push_key() :: :ok
  def push_key do
    case with_repo(&Vapid.public_key/0) do
      nil -> fail("This server has no push keys; restart the app to run its migrations.")
      key -> IO.puts(key)
    end
  end

  @doc """
  `bin/idejo-admin rotate-push-keys`: replaces the VAPID key pair, ends every browser's push
  subscription (they were made with the old key) and records `push.rotate_keys` in the audit
  log, with no admin. Browsers subscribe again with the new key when their member next opens
  a page (PN-18).
  """
  @spec rotate_push_keys() :: :ok
  def rotate_push_keys do
    {:ok, key} = with_repo(&rotate_push_keys!/0)

    IO.puts("""
    New push public key:

        #{key}

    Every browser's push subscription has ended; each subscribes again with the new key
    the next time its member opens a page.\
    """)
  end

  @doc "Rotates the VAPID keys and audits it. Returns the new public key."
  @spec rotate_push_keys!() :: {:ok, String.t()}
  def rotate_push_keys! do
    Repo.transact(fn ->
      with {:ok, key} <- Vapid.rotate(),
           ended = Idejo.Push.delete_all(),
           {:ok, _} <-
             Audit.record(nil, "push.rotate_keys", nil, %{
               "public_key" => key,
               "subscriptions_ended" => ended
             }) do
        {:ok, key}
      end
    end)
  end

  ## Health (AD-09)

  @doc """
  `bin/idejo-admin health`: prints each check and fails when one has failed. Warnings do
  not fail it.
  """
  @spec health() :: :ok
  def health do
    checks = with_repo(&health_checks/0)

    Enum.each(checks, fn {name, status, detail} ->
      IO.puts(String.pad_trailing("#{status_label(status)} #{name}", 20) <> detail)
    end)

    if Enum.any?(checks, &match?({_, :error, _}, &1)), do: fail("Some checks failed.")
    :ok
  end

  @doc """
  Runs the health checks: `{name, :ok | :warning | :error, detail}` for the server, the
  database, migrations, the owner, the push keys, the uploads directory and the last backup.
  """
  @spec health_checks() :: [{String.t(), :ok | :warning | :error, String.t()}]
  def health_checks do
    database = check_database()

    # Without a database, the checks that read it would only repeat its error.
    needs_database =
      if match?({:ok, _}, database),
        do: [
          {"migrations", check_migrations()},
          {"owner", check_owner()},
          {"push keys", check_push_keys()}
        ],
        else: []

    checks =
      [{"server", check_server()}, {"database", database}] ++
        needs_database ++ [{"uploads", check_uploads()}, {"backup", check_backup()}]

    Enum.map(checks, fn {name, {status, detail}} -> {name, status, detail} end)
  end

  defp check_server do
    if Process.whereis(IdejoWeb.Endpoint),
      do: {:ok, "running"},
      else: {:error, "not running"}
  end

  defp check_database do
    case Repo.query("SELECT 1") do
      {:ok, _} ->
        {:ok, "reachable"}

      # The pool's own message is advice for developers; the reason is in the log.
      {:error, %DBConnection.ConnectionError{}} ->
        {:error, "not reachable; the app log gives the reason (check DATABASE_URL)"}

      {:error, error} ->
        {:error, error |> Exception.message() |> String.split("\n") |> hd()}
    end
  end

  defp check_migrations do
    case Enum.count(Ecto.Migrator.migrations(Repo), &match?({:down, _, _}, &1)) do
      0 -> {:ok, "up to date"}
      pending -> {:error, "#{pending} pending; restart the app to run them"}
    end
  end

  defp check_owner do
    if Idejo.Setup.needed?(),
      do: {:warning, "none yet; open the server in a browser to run the setup wizard"},
      else: {:ok, "set up"}
  end

  defp check_push_keys do
    case Vapid.keys() do
      {:ok, _keys} ->
        {:ok, "readable"}

      {:error, :missing} ->
        {:error, "missing; restart the app to run its migrations"}

      {:error, :unreadable} ->
        {:error, "cannot be read (SECRET_KEY_BASE changed?); run rotate-push-keys"}
    end
  end

  # The directory comes from the configuration, the file name from here: nothing from users.
  # sobelow_skip ["Traversal.FileModule"]
  defp check_uploads do
    dir = Application.fetch_env!(@app, :uploads_dir)
    probe = Path.join(dir, ".health-#{System.unique_integer([:positive])}")

    # Made on first use, like `Idejo.Uploads` does.
    with :ok <- File.mkdir_p(dir), :ok <- File.write(probe, "") do
      File.rm(probe)
      {:ok, "#{dir} writable"}
    else
      {:error, reason} -> {:error, "#{dir} not writable: #{:file.format_error(reason)}"}
    end
  end

  # The nightly backup runs at 03:00 UTC: one older than a day and a bit means a night failed.
  defp check_backup do
    case Backup.list() do
      [] ->
        {:warning, "none yet; the first is made at 03:00 UTC"}

      [%{name: name, path: path} | _] ->
        {:ok, %{mtime: mtime}} = File.stat(path, time: :posix)
        hours = div(System.os_time(:second) - mtime, 3600)

        if hours < 26,
          do: {:ok, "#{name}, #{hours} h ago"},
          else: {:error, "#{name}, #{hours} h ago; see the app log for why backups fail"}
    end
  end

  defp status_label(:ok), do: "ok     "
  defp status_label(:warning), do: "warning"
  defp status_label(:error), do: "FAILED "

  ## Helpers

  # Inside the running server the repo is already started and stays so; in a fresh VM only
  # the repo starts, not the server.
  defp with_repo(fun) do
    load_app()
    {:ok, result, _} = Ecto.Migrator.with_repo(Repo, fn _repo -> fun.() end)
    result
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(string) when is_binary(string) do
    if String.trim(string) == "", do: nil, else: String.trim(string)
  end

  # Under rpc, standard output goes to the operator's terminal but standard error to the
  # server's log, so errors are printed on standard output too. Exiting, unlike
  # System.halt/1, ends only this command under rpc, never the server, and shows no
  # stacktrace.
  defp fail(message) do
    IO.puts(message)
    exit({:shutdown, 1})
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end

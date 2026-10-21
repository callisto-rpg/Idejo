# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.BackupTest do
  # Not async: these tests write the shared backup and uploads directories, and the restore
  # tests point the repo's configuration at a database of their own.
  use Idejo.DataCase, async: false
  use Oban.Testing, repo: Idejo.Repo

  import Idejo.AccountsFixtures

  alias Ecto.Adapters.Postgres
  alias Idejo.Accounts
  alias Idejo.Audit
  alias Idejo.Backup

  setup do
    File.rm_rf!(Backup.dir())
    File.rm_rf!(uploads_dir())
    File.mkdir_p!(uploads_dir())
    :ok
  end

  defp uploads_dir, do: Application.fetch_env!(:idejo, :uploads_dir)

  defp put_upload(name, content), do: File.write!(Path.join(uploads_dir(), name), content)

  defp uploads, do: uploads_dir() |> File.ls!() |> Enum.sort()

  defp archive_names(path) do
    {:ok, names} = :erl_tar.table(String.to_charlist(path))
    names |> Enum.map(&to_string/1) |> Enum.sort()
  end

  # pg_dump and pg_restore work on committed data, over their own connections: these tests
  # run on a database of their own, outside the sandbox, which the repo's configuration
  # (read by Backup for the PostgreSQL tools) and this process's dynamic repo point at.
  defp scratch_database(_context) do
    original = Application.fetch_env!(:idejo, Idejo.Repo)
    name = "idejo_test_backup#{System.get_env("MIX_TEST_PARTITION")}"

    config =
      Keyword.merge(original, database: name, pool: DBConnection.ConnectionPool, force_drop: true)

    _ = Postgres.storage_down(config)
    :ok = Postgres.storage_up(config)
    Application.put_env(:idejo, Idejo.Repo, config)
    repo = connect()
    Ecto.Migrator.run(Repo, :up, all: true, dynamic_repo: repo, log: false)

    on_exit(fn ->
      Application.put_env(:idejo, Idejo.Repo, original)
      Postgres.storage_down(config)
    end)

    :ok
  end

  # After a restore the server starts afresh; so does this process's repo, whose connections
  # hold statements prepared on the tables the restore dropped. Linked: it ends with the test.
  defp connect do
    case Repo.get_dynamic_repo() do
      Repo -> :ok
      old -> Supervisor.stop(old)
    end

    {:ok, repo} = Repo.start_link(name: nil, pool_size: 2)
    Repo.put_dynamic_repo(repo)
    repo
  end

  describe "create and restore" do
    setup :scratch_database

    @tag req: "AD-05", pg_tools: true
    test "AD-05 a backup holds the database and the uploads, and restores them" do
      alice = user_fixture(%{username: unique_username("alice")})
      put_upload("kept.webp", "kept")

      assert {:ok, backup} = Backup.create()
      assert Path.dirname(backup) == Backup.dir()
      assert Path.basename(backup) =~ ~r/\Aidejo-\d{8}-\d{6}\.tar\z/
      assert archive_names(backup) == ~w(database.dump manifest.json uploads/kept.webp)
      assert [%{path: ^backup}] = Backup.list()
      # Nothing half-written is left behind.
      assert File.ls!(Backup.dir()) == [Path.basename(backup)]

      bob = user_fixture(%{username: unique_username("bob")})
      File.rm!(Path.join(uploads_dir(), "kept.webp"))
      put_upload("later.webp", "later")

      assert {:ok, before} = Backup.restore(backup)
      connect()

      assert Accounts.get_user_by_email(alice.email)
      refute Accounts.get_user_by_email(bob.email)
      assert uploads() == ["kept.webp"]
      assert File.read!(Path.join(uploads_dir(), "kept.webp")) == "kept"

      assert [%{change: "backup.restore", admin_id: nil, after: after_} | _] =
               Audit.list_entries()

      assert after_ == %{"backup" => Path.basename(backup)}

      # The backup made first undoes the restore.
      assert before != backup
      assert {:ok, _} = Backup.restore(before)
      connect()
      assert Accounts.get_user_by_email(bob.email)
      assert uploads() == ["later.webp"]
    end
  end

  describe "restore refuses" do
    @tag req: "AD-05"
    test "AD-05 a file that is not an Idejo backup" do
      File.mkdir_p!(Backup.dir())
      missing = Path.join(Backup.dir(), "missing.tar")
      assert Backup.restore(missing) == {:error, "no such file"}

      not_tar = Path.join(Backup.dir(), "notes.tar")
      File.write!(not_tar, "hello")
      assert Backup.restore(not_tar) == {:error, "not an Idejo backup"}
    end

    @tag req: "AD-05"
    test "AD-05 an archive with names outside its place" do
      path = Path.join(Backup.dir(), "evil.tar")
      File.mkdir_p!(Backup.dir())

      :ok =
        :erl_tar.create(String.to_charlist(path), [
          {~c"manifest.json", ~s({"format":1,"migration":1})},
          {~c"uploads/../../escape.txt", "x"}
        ])

      assert Backup.restore(path) == {:error, "not an Idejo backup"}
      refute File.exists?(Path.join(uploads_dir(), "../escape.txt"))
    end

    @tag req: "AD-05"
    test "AD-05 a backup made by a newer version" do
      path = Path.join(Backup.dir(), "newer.tar")
      File.mkdir_p!(Backup.dir())
      manifest = ~s({"format":1,"migration":99990101000000})
      :ok = :erl_tar.create(String.to_charlist(path), [{~c"manifest.json", manifest}])

      assert Backup.restore(path) ==
               {:error, "made by a newer version of Idejo; upgrade it first"}

      assert Backup.list() == []
    end
  end

  describe "prune/0" do
    @tag req: "AD-05"
    test "AD-05 keeps the newest seven backups" do
      File.mkdir_p!(Backup.dir())

      names =
        for day <- 10..18 do
          "idejo-202610#{day}-030000.tar"
        end ++ ["idejo-20261018-030000-2.tar"]

      Enum.each(names, &File.write!(Path.join(Backup.dir(), &1), ""))
      File.write!(Path.join(Backup.dir(), "notes.txt"), "")

      assert Backup.prune() == ~w(idejo-20261012-030000.tar idejo-20261011-030000.tar
                                  idejo-20261010-030000.tar)

      assert [%{name: "idejo-20261018-030000-2.tar"}, %{name: "idejo-20261018-030000.tar"} | _] =
               Backup.list()

      assert length(Backup.list()) == Backup.keep()
      assert File.exists?(Path.join(Backup.dir(), "notes.txt"))
    end
  end

  describe "Worker" do
    @tag req: "AD-05"
    test "AD-05 runs every night at 03:00" do
      crontab =
        Application.fetch_env!(:idejo, Oban)[:plugins]
        |> Enum.find_value(fn
          {Oban.Plugins.Cron, opts} -> opts[:crontab]
          _ -> nil
        end)

      assert {"0 3 * * *", Backup.Worker} in crontab
    end

    @tag req: "AD-05", pg_tools: true
    test "AD-05 makes a backup and deletes the oldest" do
      File.mkdir_p!(Backup.dir())

      for day <- 10..16,
          do: File.write!(Path.join(Backup.dir(), "idejo-202610#{day}-030000.tar"), "")

      assert :ok = perform_job(Backup.Worker, %{})

      assert [%{name: newest} | _] = Backup.list()
      assert newest =~ ~r/\Aidejo-\d{8}-\d{6}\.tar\z/
      assert length(Backup.list()) == 7
      refute File.exists?(Path.join(Backup.dir(), "idejo-20261010-030000.tar"))
    end
  end
end

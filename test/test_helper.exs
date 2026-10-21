# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# TP-12: each run starts with no uploaded files.
File.rm_rf!(Application.fetch_env!(:idejo, :uploads_dir))
# AD-05: and with no backups.
File.rm_rf!(Application.fetch_env!(:idejo, :backup_dir))

# AD-05: the backup tests run pg_dump and pg_restore, matching the server's major version, from
# IDEJO_PG_BIN_DIR or the PATH. CI installs them and always runs these tests; elsewhere they
# are skipped, with a note, when the tools are missing.
pg_tools? =
  Enum.all?(~w(pg_dump pg_restore), fn tool ->
    case Application.get_env(:idejo, :pg_bin_dir) do
      nil -> System.find_executable(tool)
      bin -> File.exists?(Path.join(bin, tool))
    end
  end)

exclude =
  if pg_tools? or System.get_env("CI") do
    []
  else
    IO.puts("pg_dump or pg_restore not found: skipping the tests tagged pg_tools (AD-05).")
    [pg_tools: true]
  end

ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Idejo.Repo, :manual)

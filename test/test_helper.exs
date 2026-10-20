# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# TP-12: each run starts with no uploaded files.
File.rm_rf!(Application.fetch_env!(:idejo, :uploads_dir))

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Idejo.Repo, :manual)

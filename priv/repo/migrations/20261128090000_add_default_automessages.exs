# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddDefaultAutomessages do
  use Ecto.Migration

  # Steward decision, 2026-11-01: every install starts with !tutorial-message,
  # !tutorial-commands and !rules, sent by the server account `idejo`. They are ordinary
  # automessages: administrators change or delete them. Skipped when a member already has
  # the username, and a command already there is kept.
  def up do
    execute(fn ->
      case sender() do
        nil ->
          :ok

        sender_id ->
          now = DateTime.utc_now(:second)

          for {command, body} <- Idejo.Messages.Automessages.Defaults.all() do
            repo().query!(
              """
              INSERT INTO automessages (id, command, body_md, sender_id, created_at, updated_at)
              VALUES ($1, $2, $3, $4, $5, $5) ON CONFLICT (command) DO NOTHING
              """,
              [Ecto.UUID.dump!(Ecto.UUID.generate()), command, body, sender_id, now]
            )
          end
      end
    end)
  end

  def down do
    execute(fn ->
      repo().query!("DELETE FROM automessages WHERE command = ANY($1)", [
        Enum.map(Idejo.Messages.Automessages.Defaults.all(), &elem(&1, 0))
      ])
    end)
  end

  # The `idejo` server account, made when nobody has the name.
  defp sender do
    case repo().query!("SELECT id, status FROM users WHERE username = 'idejo'").rows do
      [[id, "system"]] -> id
      [_] -> nil
      [] -> create_sender()
    end
  end

  defp create_sender do
    id = Idejo.Federation.generate_id()
    uri = Idejo.Federation.uri(:user, id)
    now = DateTime.utc_now(:second)
    dumped = Ecto.UUID.dump!(id)

    repo().query!(
      """
      INSERT INTO users (id, uri, email, username, display_name, password_hash, status,
        origin, welcomed_at, created_at, updated_at)
      VALUES ($1, $2, $3, 'idejo', 'idejo', $4, 'system', 'local', $5, $5, $5)
      """,
      [dumped, uri, "system:" <> id, Argon2.hash_pwd_salt(:crypto.strong_rand_bytes(32)), now]
    )

    repo().query!(
      """
      INSERT INTO activities (id, actor_uri, verb, object_uri, payload, created_at)
      VALUES ($1, $2, 'create', $2, $3, $4)
      """,
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        uri,
        %{"type" => "Service", "username" => "idejo", "name" => "idejo"},
        now
      ]
    )

    dumped
  end
end

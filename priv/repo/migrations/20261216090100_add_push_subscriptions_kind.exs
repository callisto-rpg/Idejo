# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Repo.Migrations.AddPushSubscriptionsKind do
  use Ecto.Migration

  # AP-19 (steward decision, 2026-11-10): an app's UnifiedPush endpoint is a subscription
  # too, of kind "unifiedpush", tied to the device token that made it instead of a browser
  # session, so it ends with that token (PN-13).
  def change do
    alter table(:push_subscriptions) do
      add :kind, :string, null: false, default: "web"
      add :name, :string, size: 64
      add :api_token_id, references(:api_tokens, type: :binary_id, on_delete: :delete_all)
    end

    create index(:push_subscriptions, [:api_token_id])
  end
end

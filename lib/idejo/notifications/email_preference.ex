# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Notifications.EmailPreference do
  @moduledoc """
  What a user's email summary counts (steward decision, 2026-10-23; `Idejo.Notifications.Digest`).
  A user without a row has the defaults: mentions and replies, and new messages in topics
  they started, at most one summary a week while they stay away.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @options [:mentions, :role_mentions, :own_topics, :followed_topics, :new_topics, :all_activity]

  @primary_key false
  @foreign_key_type :binary_id
  schema "email_preferences" do
    belongs_to :user, Idejo.Accounts.User, primary_key: true
    field :mentions, :boolean, default: true
    field :role_mentions, :boolean, default: false
    field :own_topics, :boolean, default: true
    field :followed_topics, :boolean, default: false
    field :new_topics, :boolean, default: false
    field :all_activity, :boolean, default: false
    field :once_a_week, :boolean, default: true
    field :digest_sent_at, :utc_datetime_usec
    field :unsubscribe_token, :string

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end

  @doc "What a summary may count, in the order the profile lists them."
  @spec options() :: [atom()]
  def options, do: @options

  @doc "A changeset for the profile's choices."
  def changeset(preference, attrs), do: cast(preference, attrs, @options ++ [:once_a_week])
end

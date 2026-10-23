# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.Topic do
  @moduledoc """
  A topic (TP-01): a title in one category, opened by its first message. Read at
  `/t/{id}/{slug}`; the slug comes from the title and only makes the address readable, the id
  finds the topic. Every topic has a stable URI (FD-01).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "topics" do
    field :uri, :string
    field :title, :string
    field :slug, :string
    field :state, :string, default: "open"
    field :pinned, :boolean, default: false
    # Followed by everyone who may view it, unless they unfollow it (steward decision,
    # 2026-10-23; Idejo.Reading).
    field :autofollow, :boolean, default: false
    field :message_count, :integer, default: 0
    field :last_activity_at, :utc_datetime_usec
    belongs_to :category, Idejo.Forum.Category
    belongs_to :author, Idejo.Accounts.User
    # TP-09: the message this topic was started from, if any.
    belongs_to :forked_from, Idejo.Messages.Message, foreign_key: :forked_from_message_id
    has_many :messages, Idejo.Messages.Message
    # TP-19: one or more tags, server-wide or of the topic's category.
    many_to_many :tags, Idejo.Forum.Tag, join_through: "topic_tags", on_replace: :delete

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @title_max 150

  @doc """
  A changeset for a new topic's title. The caller sets everything else.
  """
  def create_changeset(topic, attrs) do
    topic
    |> cast(attrs, [:title])
    |> update_change(:title, &(&1 && String.trim(&1)))
    |> validate_required([:title])
    |> validate_length(:title, max: @title_max)
    |> validate_required([:id, :uri, :category_id, :author_id, :slug, :last_activity_at])
  end
end

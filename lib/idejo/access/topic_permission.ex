# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Access.TopicPermission do
  @moduledoc """
  One right of one role on one topic (steward request, 2026-11-13), over the topic's
  category: `effect` `"allow"` or `"deny"`; no row means the category's setting
  (`Idejo.Access.CategoryPermission`). Rights: view, post, moderate and edit tags (starting
  topics belongs to categories).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @rights ~w(view post moderate tag)a

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "topic_permissions" do
    belongs_to :topic, Idejo.Forum.Topic
    belongs_to :role, Idejo.Access.Role
    field :right, :string
    field :effect, :string

    timestamps(type: :utc_datetime)
  end

  @doc "The rights a topic can set: view, post, moderate and edit tags."
  @spec rights() :: [atom()]
  def rights, do: @rights
end

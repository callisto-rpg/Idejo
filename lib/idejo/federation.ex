# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Federation do
  @moduledoc """
  Stable URIs (FD-01) and the activities outbox (FD-02).

  Every user, category, topic and message gets a URI when it is created; it is stored and
  never recomputed, so it stays the same even if routes change. Significant events are
  recorded as activities, ready for federation later.
  """

  alias Idejo.Federation.Activity

  @kinds %{user: "u", category: "c", topic: "t", message: "m"}

  @doc """
  Generates a primary key for a new record. UUIDv7 keeps keys time-ordered.
  """
  @spec generate_id() :: Ecto.UUID.t()
  def generate_id, do: Ecto.UUID.generate(version: 7)

  @doc """
  Builds the stable URI for a record of the given kind and id.

      iex> Idejo.Federation.uri(:user, "0199f1c2-0000-7000-8000-000000000000")
      "http://localhost:4000/u/0199f1c2-0000-7000-8000-000000000000"
  """
  @spec uri(:user | :category | :topic | :message, Ecto.UUID.t()) :: String.t()
  def uri(kind, id) when is_map_key(@kinds, kind) and is_binary(id) do
    Application.fetch_env!(:idejo, :base_uri) <> "/" <> Map.fetch!(@kinds, kind) <> "/" <> id
  end

  @doc """
  Returns a changeset for an activity. Insert it in the same transaction as the change it
  records, so an event is never lost or recorded without its change.
  """
  @spec activity_changeset(map()) :: Ecto.Changeset.t()
  def activity_changeset(attrs), do: Activity.changeset(%Activity{}, attrs)
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Message do
  @moduledoc """
  A message in a topic (MVP §6), stored twice: Markdown source and sanitised HTML (FD-03).

  The columns of a growing message are here from the start: `opened_at`, `closes_at` (fixed
  at the first commit, GM-03) and `closed_at`. Until growing messages arrive (M3) every
  message is posted closed, and the first message of a topic always is (GM-14).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "messages" do
    field :uri, :string
    field :state, :string
    field :opened_at, :utc_datetime_usec
    field :closes_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec
    field :body_md, :string
    field :body_html, :string
    field :edited, :boolean, default: false
    belongs_to :topic, Idejo.Forum.Topic
    belongs_to :author, Idejo.Accounts.User
    belongs_to :reply_to, __MODULE__

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  A changeset for a message posted closed, such as a topic's first message (GM-14). The
  caller sets `id`, `uri`, `topic_id`, `author_id` and the times.
  """
  def closed_changeset(message, attrs) do
    message
    |> cast(attrs, [:body_md])
    |> validate_required([:body_md], message: "can't be blank")
    |> validate_change(:body_md, fn :body_md, body ->
      if String.trim(body) == "", do: [body_md: "can't be blank"], else: []
    end)
    |> put_html()
    |> put_change(:state, "closed")
    |> validate_required([:id, :uri, :topic_id, :author_id, :opened_at, :closes_at, :closed_at])
  end

  defp put_html(%Ecto.Changeset{valid?: true, changes: %{body_md: body}} = changeset),
    do: put_change(changeset, :body_html, Idejo.Markdown.to_html(body))

  defp put_html(changeset), do: changeset
end

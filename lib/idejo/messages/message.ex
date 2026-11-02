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

  alias Idejo.Messages.Body

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
    # Posted by `!schedule` at the time its author chose (steward decision, 2026-10-23).
    field :scheduled, :boolean, default: false
    # `!spoiler`: readers see it blurred until they reveal it (steward decision, 2026-10-23).
    field :spoiler, :boolean, default: false
    # `!spoiler:overlay text:` (steward decision, 2026-10-28): what the cover says, or nil.
    field :spoiler_label, :string
    # MO-02: deleted by a moderator; readers see a placeholder, moderators the text.
    field :deleted_at, :utc_datetime_usec
    belongs_to :deleted_by, Idejo.Accounts.User
    belongs_to :topic, Idejo.Forum.Topic
    belongs_to :author, Idejo.Accounts.User
    belongs_to :reply_to, __MODULE__
    # The automessage it was posted from (Idejo.Messages.Automessages), for its cooldown.
    field :automessage_id, Ecto.UUID
    # The role shown next to the author's name, worked out once by Idejo.Messages.broadcast/2
    # for every viewer of the topic (NF-04): a role, nil (none shown), or :unknown.
    field :author_role, :any, virtual: true, default: :unknown
    # Earlier versions, kept only when sent text was changed (GM-11, TP-05).
    has_many :versions, Idejo.Messages.Version, preload_order: [asc: :created_at]

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  A changeset for a message posted closed, such as a topic's first message (GM-14). The
  caller sets `id`, `uri`, `topic_id`, `author_id` and the times; `context` is how its
  inline links resolve (`Idejo.Messages.Body.to_html/2`), by default its author in its topic.
  """
  def closed_changeset(message, attrs, context \\ nil) do
    message
    |> cast(attrs, [:body_md])
    |> validate_required([:body_md], message: "can't be blank")
    |> validate_change(:body_md, fn :body_md, body ->
      if String.trim(body) == "", do: [body_md: "can't be blank"], else: []
    end)
    |> put_html(context || Body.context(message))
    |> put_change(:state, "closed")
    |> validate_required([:id, :uri, :topic_id, :author_id, :opened_at, :closes_at, :closed_at])
  end

  defp put_html(%Ecto.Changeset{valid?: true, changes: %{body_md: body}} = changeset, context),
    do: put_change(changeset, :body_html, Body.to_html(body, context))

  defp put_html(changeset, _context), do: changeset
end

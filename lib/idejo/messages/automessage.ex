# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Automessage do
  @moduledoc """
  An automessage (steward decision, 2026-11-01): a `!command` that moderators type in the
  composer to have the server post `body_md` in the topic, sent by `sender`, a server
  account (`users.status` "system"). Made in **Admin → Automessages**
  (`Idejo.Messages.Automessages`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "automessages" do
    field :command, :string
    field :body_md, :string
    field :body_html, :string
    belongs_to :sender, Idejo.Accounts.User
    # The sender's username in the form; the sender account is found or made from it.
    field :sender_username, :string, virtual: true

    timestamps(type: :utc_datetime, inserted_at: :created_at)
  end

  @doc """
  A changeset for the form: the command (without `!`), the text and the sender's username.
  `reserved` are the composer's own commands, which an automessage never takes.
  """
  def changeset(automessage, attrs, reserved) do
    automessage
    |> cast(attrs, [:command, :body_md, :sender_username])
    |> update_change(:command, &normalise_command/1)
    |> update_change(:sender_username, &String.trim/1)
    |> validate_required([:command, :body_md, :sender_username])
    |> validate_format(:command, ~r/^[a-z0-9][a-z0-9_-]*$/,
      message: "may only contain letters, digits, - and _"
    )
    |> validate_length(:command, max: 30)
    |> validate_exclusion(:command, reserved, message: "is one of the composer's own commands")
    |> validate_change(:body_md, fn :body_md, body ->
      if String.trim(body) == "", do: [body_md: "can't be blank"], else: []
    end)
    |> validate_format(:sender_username, ~r/^[A-Za-z0-9_]+$/,
      message: "may only contain letters, digits and underscores"
    )
    |> validate_length(:sender_username, min: 3, max: 30)
    |> unsafe_validate_unique(:command, Idejo.Repo, message: "is already an automessage")
    |> unique_constraint(:command, message: "is already an automessage")
  end

  # Typed with or without its `!`, in any case.
  defp normalise_command(command),
    do: command |> String.trim() |> String.trim_leading("!") |> String.downcase()
end

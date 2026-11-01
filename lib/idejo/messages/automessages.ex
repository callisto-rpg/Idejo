# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Automessages do
  @moduledoc """
  Automessages (steward decision, 2026-11-01): administrators make `!command`s in **Admin →
  Automessages**, each with a text and a sender; a moderator of a topic's category who
  types the command in the composer has the server post that text there (`post/3`).

  The sender is a server account: a `users` row with `status: "system"`, found or made from
  the username the form gives (`idejo` by default), whose display name is that username. It
  never signs in (an email that cannot be typed, a random password, never confirmed) and,
  not being active, is never mentioned, suggested, notified or emailed. Automessages with
  the same username share the account and its picture; a new account gets the default
  picture (`priv/static/images/idejo-pfp.png`) until one is uploaded. A username a member
  already has is refused. Accounts stay when no automessage names them any more: their
  messages keep their author.

  Every change is audited (`automessage.create|update|delete`, SP-06); every post is logged
  as the moderator's (`message.automessage`, MO-03).
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Federation
  alias Idejo.Forum.Category
  alias Idejo.Forum.Topic
  alias Idejo.Messages
  alias Idejo.Messages.Automessage
  alias Idejo.Messages.Body
  alias Idejo.Messages.Message
  alias Idejo.Moderation
  alias Idejo.RateLimit
  alias Idejo.Repo

  # The composer's own commands (IdejoWeb.ComposerCommands.all/0), never an automessage's.
  @reserved ~w(image new-topic poll schedule spoiler)

  @default_username "idejo"

  @doc "The composer's own command names, which automessages may not take."
  @spec reserved() :: [String.t()]
  def reserved, do: @reserved

  @doc "The sender username a new automessage's form starts with."
  @spec default_username() :: String.t()
  def default_username, do: @default_username

  @doc "The picture a new server account gets."
  @spec default_picture() :: Path.t()
  def default_picture, do: Application.app_dir(:idejo, "priv/static/images/idejo-pfp.png")

  @doc "Every automessage, by command, with its sender."
  @spec list() :: [Automessage.t()]
  def list do
    Repo.all(from a in Automessage, order_by: a.command, preload: :sender)
  end

  @doc "The commands' names and what they post, for the composer's list (moderators only)."
  @spec commands() :: [%{name: String.t(), sender: String.t()}]
  def commands do
    Repo.all(
      from a in Automessage,
        join: s in assoc(a, :sender),
        order_by: a.command,
        select: %{name: a.command, sender: s.username}
    )
  end

  @doc "Returns a changeset for an automessage's form."
  def change(automessage \\ %Automessage{}, attrs \\ %{}) do
    automessage
    |> with_username()
    |> Automessage.changeset(attrs, @reserved)
  end

  defp with_username(%Automessage{sender: %User{username: username}} = a),
    do: %{a | sender_username: username}

  defp with_username(%Automessage{} = a), do: %{a | sender_username: @default_username}

  @doc """
  Creates an automessage, as `admin`. `picture`, a path, becomes its sender's picture.
  """
  @spec create(User.t(), map(), Path.t() | nil) ::
          {:ok, Automessage.t()} | {:error, Changeset.t() | atom()}
  def create(%User{} = admin, attrs, picture \\ nil),
    do: save(admin, %Automessage{}, attrs, picture, "automessage.create")

  @doc "Changes an automessage's command, text or sender, as `admin`."
  @spec update(User.t(), Automessage.t(), map(), Path.t() | nil) ::
          {:ok, Automessage.t()} | {:error, Changeset.t() | atom()}
  def update(%User{} = admin, %Automessage{} = automessage, attrs, picture \\ nil),
    do: save(admin, automessage, attrs, picture, "automessage.update")

  defp save(admin, automessage, attrs, picture, action) do
    automessage = Repo.preload(automessage, :sender)
    changeset = change(automessage, attrs)

    Repo.transact(fn ->
      with {:ok, changeset} <- valid(changeset),
           {:ok, sender} <- sender(changeset),
           {:ok, sender} <- set_picture(sender, picture),
           {:ok, saved} <-
             changeset
             |> Changeset.put_change(:sender_id, sender.id)
             |> Changeset.put_change(:body_html, to_html(changeset, admin))
             |> Repo.insert_or_update(),
           saved = %{saved | sender: sender},
           {:ok, _} <- audit(admin, action, automessage, saved) do
        {:ok, saved}
      end
    end)
  end

  defp valid(%Changeset{valid?: true} = changeset), do: {:ok, changeset}
  defp valid(changeset), do: {:error, Map.put(changeset, :action, :validate)}

  # The server account named in the form: the one already there, or a new one.
  defp sender(changeset) do
    username = Changeset.get_field(changeset, :sender_username)

    case Repo.one(from u in User, where: u.username == ^username) do
      %User{status: "system"} = user ->
        {:ok, user}

      %User{} ->
        {:error,
         changeset
         |> Changeset.add_error(:sender_username, "belongs to a member")
         |> Map.put(:action, :validate)}

      nil ->
        create_sender(username)
    end
  end

  defp create_sender(username) do
    id = Federation.generate_id()
    now = DateTime.utc_now(:second)

    # Never signed in with: the email has no @ (sign-up and sign-in need one), the password is
    # random and nobody knows it.
    user =
      Repo.insert!(%User{
        id: id,
        uri: Federation.uri(:user, id),
        email: "system:" <> id,
        username: username,
        display_name: username,
        password_hash: Argon2.hash_pwd_salt(:crypto.strong_rand_bytes(32)),
        status: "system",
        welcomed_at: now
      })

    Repo.insert!(
      Federation.activity_changeset(%{
        actor_uri: user.uri,
        verb: "create",
        object_uri: user.uri,
        payload: %{"type" => "Service", "username" => username, "name" => username}
      })
    )

    {:ok, user}
  end

  # The picture uploaded with the form, else the default one for an account without any.
  defp set_picture(%User{avatar_id: id} = sender, nil) when id != nil, do: {:ok, sender}
  defp set_picture(sender, nil), do: Accounts.set_avatar(sender, default_picture())
  defp set_picture(sender, picture), do: Accounts.set_avatar(sender, picture)

  @doc "Deletes an automessage, as `admin`. Its sender account stays, with its messages."
  @spec delete(User.t(), Automessage.t()) :: {:ok, Automessage.t()} | {:error, term()}
  def delete(%User{} = admin, %Automessage{} = automessage) do
    automessage = Repo.preload(automessage, :sender)

    Repo.transact(fn ->
      with {:ok, deleted} <- Repo.delete(automessage),
           {:ok, _} <- Audit.record(admin, "automessage.delete", snapshot(automessage), nil) do
        {:ok, deleted}
      end
    end)
  end

  defp audit(admin, "automessage.create", _before, saved),
    do: Audit.record(admin, "automessage.create", nil, snapshot(saved))

  defp audit(admin, action, before, saved),
    do: Audit.record(admin, action, snapshot(before), snapshot(saved))

  defp snapshot(%Automessage{sender: sender} = automessage) do
    automessage
    |> Audit.snapshot([:command, :body_md])
    |> Map.put("sender", sender && sender.username)
  end

  @doc "The HTML of an automessage's Markdown as `admin` sees it, for the form's preview."
  @spec preview(String.t(), User.t()) :: String.t()
  def preview(markdown, %User{} = admin), do: Body.to_html(markdown, author: admin)

  defp to_html(changeset, admin), do: preview(Changeset.get_field(changeset, :body_md), admin)

  @doc """
  Whether `user` may send automessages in `topic`: the `:moderate` right in its category
  (owners and administrators always), in an open topic. Never in a private conversation.
  """
  @spec may_send?(User.t() | nil, Topic.t()) :: boolean()
  def may_send?(%User{} = user, %Topic{state: "open", private: false, category_id: id})
      when is_binary(id),
      do: Access.can?(user, :moderate, %Category{id: id})

  def may_send?(_user, _topic), do: false

  @doc """
  Posts the automessage `command` (without `!`) in `topic`, for `moderator`: a closed
  message by its sender, with its inline links (TP-10) resolved as the moderator may view
  them, notified like any new message (NO-01) and logged as the moderator's
  (`message.automessage`, MO-03). Then broadcast (TP-04).

  `{:error, :forbidden}` without `may_send?/2`, `{:error, :not_found}` for an unknown
  command, `{:error, :rate_limited}` past the moderator's `:new_message` limit.
  """
  @spec post(User.t(), Topic.t(), String.t()) ::
          {:ok, Message.t()} | {:error, :forbidden | :not_found | :rate_limited | term()}
  def post(%User{} = moderator, %Topic{} = topic, command) when is_binary(command) do
    result =
      Repo.transact(fn ->
        # Locked, so a lock or a move cannot slip in between the check and the insert.
        topic = Repo.one!(from t in Topic, where: t.id == ^topic.id, lock: "FOR UPDATE")
        automessage = Repo.get_by(Automessage, command: command)

        cond do
          not may_send?(moderator, topic) -> {:error, :forbidden}
          automessage == nil -> {:error, :not_found}
          RateLimit.check(:new_message, moderator.id) != :ok -> {:error, :rate_limited}
          true -> insert(moderator, topic, Repo.preload(automessage, :sender))
        end
      end)

    with {:ok, message} <- result, do: Messages.broadcast(topic.id, {:message, message})
    result
  end

  defp insert(moderator, topic, %Automessage{sender: sender} = automessage) do
    now = DateTime.utc_now()
    id = Federation.generate_id()

    with {:ok, message} <-
           %Message{
             id: id,
             uri: Federation.uri(:message, id),
             topic_id: topic.id,
             author_id: sender.id,
             opened_at: now,
             closes_at: now,
             closed_at: now
           }
           |> Message.closed_changeset(%{body_md: automessage.body_md},
             author: moderator,
             topic_id: topic.id
           )
           |> Repo.insert(),
         {:ok, _} <-
           topic
           |> Changeset.change(message_count: topic.message_count + 1, last_activity_at: now)
           |> Repo.update(),
         {:ok, _} <- Idejo.Notifications.notify_new(message, topic),
         {:ok, _} <- Repo.insert(activity(sender, message, topic)),
         {:ok, _} <-
           Moderation.record(moderator, "message.automessage", message,
             details: %{"command" => automessage.command, "sender" => sender.username}
           ) do
      {:ok, message}
    end
  end

  defp activity(sender, message, topic) do
    Federation.activity_changeset(%{
      actor_uri: sender.uri,
      verb: "create",
      object_uri: message.uri,
      target_uri: topic.uri,
      payload: %{"type" => "Note"}
    })
  end
end

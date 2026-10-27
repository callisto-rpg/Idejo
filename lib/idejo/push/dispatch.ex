# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.Dispatch do
  @moduledoc """
  Pushes one notification to one user (PN-01 to PN-03), in the `push` queue. Args:
  `"user_id"` and `"message_id"`; the kind is the notification's when the job runs, so a
  mention that upgraded a role mention meanwhile is pushed as the mention.

  When it runs, in this order, nothing is pushed:

    * while push is off (PN-19);
    * when the notification was pushed already (PN-05: one push per user per message) or is
      not a reply, @mention or +role mention;
    * when the message was deleted, the account is no longer active or is banned, or the
      user may no longer view the topic (PN-10);
    * when the topic is muted (PN-09, `Idejo.Push.allowed?/3`) or the user switched that
      type off (PN-11);
    * while the user has a live view of the topic (PN-08: the in-app notification is enough);
    * when nothing of that kind is unread any more (it was read meanwhile).

  Otherwise it marks the notification pushed and sends the payload of `Idejo.Push.Payload`
  to every browser of the user (`Idejo.Push.deliver/3`).

  Changes to this module get an extra careful human review (DV-06).
  """
  use Oban.Worker,
    queue: :push,
    max_attempts: 3,
    unique: [keys: [:user_id, :message_id], states: :incomplete]

  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Forum.Category
  alias Idejo.Messages.{Authors, Message}
  alias Idejo.Notifications.Notification
  alias Idejo.Push
  alias Idejo.Push.Payload
  alias Idejo.Repo

  @kinds ~w(reply mention role_mention)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "message_id" => message_id}}) do
    with :ok <- check(Push.enabled?(), :disabled),
         {:ok, notification} <- notification(user_id, message_id),
         {:ok, message} <- message(message_id),
         {:ok, user} <- user(user_id),
         :ok <- check(may_view?(user, message), :no_view),
         :ok <- check(Push.allowed?(user, message.topic, notification.kind), :not_allowed),
         :ok <- check(Push.wants?(Push.preferences(user), notification.kind), :switched_off),
         :ok <- check(not Authors.present?(message.topic_id, user.id), :on_screen),
         {:ok, payload, urgency} <- Payload.build(user, message, notification.kind),
         :ok <- mark_pushed(notification) do
      case Push.deliver(user, payload, urgency: urgency) do
        {:ok, _queued} -> :ok
        {:error, reason} -> {:cancel, reason}
      end
    else
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp notification(user_id, message_id) do
    case Repo.one(
           from n in Notification, where: n.user_id == ^user_id and n.message_id == ^message_id
         ) do
      %Notification{pushed_at: nil, kind: kind} = notification when kind in @kinds ->
        {:ok, notification}

      _ ->
        {:error, :nothing_to_push}
    end
  end

  defp message(message_id) do
    case Repo.get(Message, message_id) do
      %Message{deleted_at: nil} = message -> {:ok, Repo.preload(message, [:author, :topic])}
      _ -> {:error, :deleted}
    end
  end

  defp user(user_id) do
    case Repo.get(User, user_id) do
      %User{status: "active"} = user ->
        if Accounts.banned?(user), do: {:error, :banned}, else: {:ok, user}

      _ ->
        {:error, :no_account}
    end
  end

  # Private conversations (steward decision, 2026-10-27) are not pushed yet: their counts
  # and titles (Reading.unread_notified/3) go through categories.
  defp may_view?(_user, %{topic: %{private: true}}), do: false

  defp may_view?(user, message),
    do: Access.can?(user, :view, Repo.get!(Category, message.topic.category_id))

  # Marked before sending, by whoever gets there first: a second job never pushes it again.
  defp mark_pushed(notification) do
    case Repo.update_all(
           from(n in Notification, where: n.id == ^notification.id and is_nil(n.pushed_at)),
           set: [pushed_at: DateTime.utc_now()]
         ) do
      {1, _} -> :ok
      _ -> {:error, :nothing_to_push}
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push do
  @moduledoc """
  Web push notifications (NO-05, PN-01 to PN-24; steward decision, 2026-10-24): standard Web
  Push (RFC 8030, 8291, 8292), with no vendor SDK or relay of our own.

  The server's VAPID keys are in `Idejo.Push.Vapid`. The "Push notifications" setting
  (PN-19, `push_enabled`, on by default) turns the whole feature off: no banner, no
  subscribing and no sending.

  Browsers that take pushes are `Idejo.Push.Subscription`s (PN-13): at most
  10 per user, the oldest removed past that, each tied to the sign-in session that made it
  and deleted when that session ends (sign-out, password reset or change, ban, account
  deletion), and all of them when the VAPID keys are rotated. Their endpoints are checked by
  `Idejo.Push.Endpoint` (PN-16).

  `deliver/3` sends a payload to every browser of a user: one `Idejo.Push.Worker` job each,
  in the `push` queue (PN-15).

  `dispatch/1` takes the in-app notifications of a message once they are committed
  (`Idejo.Notifications.announce/1`) and queues an `Idejo.Push.Dispatch` job for each reply,
  @mention or +role mention of a user with a browser taking pushes (PN-01 to PN-03). That job
  checks everything again when it runs, then builds the payload (`Idejo.Push.Payload`).
  Each user switches each type on or off (PN-11, `preferences/1`).

  Changes to this module get an extra careful human review (DV-06).
  """
  import Ecto.Query

  alias Idejo.Access.{Role, UserRole}
  alias Idejo.Accounts.User
  alias Idejo.Forum.Topic
  alias Idejo.Push.{Dispatch, Endpoint, FollowedWorker, Preference, Subscription, Worker}
  alias Idejo.RateLimit
  alias Idejo.Reading.Follow
  alias Idejo.Repo
  alias Idejo.Settings

  @max_per_user 10
  # PN-12: the encrypted body stays under 3 KB; encryption adds 103 bytes (header, delimiter
  # and tag, `Idejo.Push.Crypto`).
  @max_payload 3072 - 103 - 1
  @ttl 24 * 3600

  @doc "Whether push notifications are on for this server (PN-19)."
  @spec enabled?() :: boolean()
  def enabled?, do: Settings.get(:push_enabled) == "on"

  @doc "How many browsers one user may have taking pushes (PN-13)."
  @spec max_per_user() :: pos_integer()
  def max_per_user, do: @max_per_user

  @doc """
  Saves the browser subscription `attrs` (`"endpoint"`, `"keys"` with `"p256dh"` and
  `"auth"`, as `PushSubscription.toJSON()` gives them) for `user`, made in the sign-in
  session `session_id`. The same endpoint saved again (PN-18 syncs it at every page load)
  updates its row, now for this user and session. Past #{@max_per_user} the user's oldest
  subscriptions are deleted.

  Refused when push is off (`:disabled`), too often (`:rate_limited`, SP-05), or when the
  endpoint may not be reached (`Idejo.Push.Endpoint.reason()`, PN-16).
  """
  @spec subscribe(User.t(), String.t() | nil, map(), String.t() | nil) ::
          {:ok, Subscription.t()}
          | {:error, :disabled | :rate_limited | Endpoint.reason() | Ecto.Changeset.t()}
  def subscribe(%User{} = user, session_id, attrs, user_agent \\ nil) do
    keys = if is_map(attrs["keys"]), do: attrs["keys"], else: %{}

    fields = %{
      "endpoint" => attrs["endpoint"],
      "p256dh" => keys["p256dh"],
      "auth" => keys["auth"]
    }

    changeset = Subscription.changeset(%Subscription{}, fields)

    with :ok <- if(enabled?(), do: :ok, else: {:error, :disabled}),
         :ok <- RateLimit.check(:push_subscribe, user.id),
         {:ok, valid} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, _uri, _addresses} <- Endpoint.check(valid.endpoint) do
      Repo.transact(fn -> save(user, session_id, valid, user_agent) end)
    end
  end

  defp save(user, session_id, %Subscription{} = valid, user_agent) do
    now = DateTime.utc_now()

    subscription = %Subscription{
      valid
      | user_id: user.id,
        session_id: session_id,
        user_agent: user_agent && String.slice(user_agent, 0, 255),
        created_at: now,
        updated_at: now
    }

    saved =
      Repo.insert!(subscription,
        on_conflict:
          {:replace,
           [:user_id, :p256dh, :auth, :user_agent, :session_id, :failure_count, :updated_at]},
        conflict_target: :endpoint,
        returning: true
      )

    keep =
      from s in Subscription,
        where: s.user_id == ^user.id,
        order_by: [desc: s.created_at, desc: s.id],
        limit: @max_per_user,
        select: s.id

    Repo.delete_all(
      from s in Subscription, where: s.user_id == ^user.id and s.id not in subquery(keep)
    )

    {:ok, saved}
  end

  @doc """
  Replaces the subscription saved with `old_endpoint` by the new one in `attrs` (PN-17: the
  push service replaced it), keeping its user and session. The new endpoint is checked like
  any other (PN-16); a row that already had it gives way.
  """
  @spec renew(String.t(), map()) ::
          {:ok, Subscription.t()}
          | {:error, :not_found | :disabled | Endpoint.reason() | Ecto.Changeset.t()}
  def renew(old_endpoint, attrs) when is_binary(old_endpoint) and is_map(attrs) do
    keys = if is_map(attrs["keys"]), do: attrs["keys"], else: %{}

    fields = %{
      "endpoint" => attrs["endpoint"],
      "p256dh" => keys["p256dh"],
      "auth" => keys["auth"]
    }

    with :ok <- if(enabled?(), do: :ok, else: {:error, :disabled}),
         %Subscription{} = old <-
           Repo.get_by(Subscription, endpoint: old_endpoint) || {:error, :not_found},
         changeset = Subscription.changeset(old, fields),
         {:ok, valid} <- Ecto.Changeset.apply_action(changeset, :update),
         {:ok, _uri, _addresses} <- Endpoint.check(valid.endpoint) do
      Repo.transact(fn ->
        Repo.delete_all(
          from s in Subscription, where: s.endpoint == ^valid.endpoint and s.id != ^old.id
        )

        changeset |> Ecto.Changeset.change(failure_count: 0) |> Repo.update()
      end)
    end
  end

  @doc """
  Sends `payload` (the declarative JSON map, PN-12) to every browser of `user`: one job each
  in the `push` queue, sent with a TTL of 24 hours and `urgency` (`"normal"` by default, or
  `"high"`). Returns how many were queued; `{:error, :too_large}` when the payload would not
  stay under 3 KB encrypted.
  """
  @spec deliver(User.t(), map(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :disabled | :too_large}
  def deliver(%User{} = user, payload, opts \\ []) when is_map(payload) do
    urgency = Keyword.get(opts, :urgency, "normal")

    cond do
      not enabled?() ->
        {:error, :disabled}

      byte_size(Jason.encode!(payload)) > @max_payload ->
        {:error, :too_large}

      true ->
        jobs =
          for subscription <- list_subscriptions(user) do
            Worker.new(%{
              "subscription_id" => subscription.id,
              "payload" => payload,
              "ttl" => @ttl,
              "urgency" => urgency
            })
          end

        {:ok, length(Oban.insert_all(jobs))}
    end
  end

  @doc "The largest payload, in bytes of JSON, that stays under 3 KB encrypted (PN-12)."
  @spec max_payload() :: pos_integer()
  def max_payload, do: @max_payload

  @doc """
  The VAPID contact (`sub`, PN-14): the email of the server's first owner, else the address
  emails are sent from.
  """
  @spec contact() :: String.t()
  def contact do
    owner =
      Repo.one(
        from u in User,
          join: ur in UserRole,
          on: ur.user_id == u.id,
          join: r in Role,
          on: r.id == ur.role_id,
          where: r.built_in and r.name == "owner",
          order_by: [asc: u.created_at],
          limit: 1,
          select: u.email
      )

    "mailto:" <> (owner || Settings.get(:mail_from))
  end

  @pushed ~w(reply mention role_mention)

  @doc """
  Queues the pushes a message's notifications call for, only for users with a browser
  taking pushes and nothing while push is off. Takes the entries
  `Idejo.Notifications.announce/1` has: `%{user_id, kind, message_id}`.

    * reply, mention, role_mention (PN-01 to PN-03): one `Idejo.Push.Dispatch` job per user
      and message;
    * follow (PN-04): one `Idejo.Push.FollowedWorker` job per user, at most one waiting,
      due when the last one went `push_followed_interval_minutes` ago (now, if it is longer).
  """
  @spec dispatch([%{user_id: Ecto.UUID.t(), kind: String.t(), message_id: Ecto.UUID.t()}]) ::
          :ok
  def dispatch(entries) do
    entries = Enum.filter(entries, &(&1.kind in ["follow" | @pushed]))

    if entries != [] and enabled?() do
      subscribed = subscribed(entries |> Enum.map(& &1.user_id) |> Enum.uniq())
      {followed, pushed} = Enum.split_with(entries, &(&1.kind == "follow"))

      for entry <- pushed, MapSet.member?(subscribed, entry.user_id) do
        Oban.insert!(
          Dispatch.new(%{"user_id" => entry.user_id, "message_id" => entry.message_id})
        )
      end

      followed
      |> Enum.map(& &1.user_id)
      |> Enum.uniq()
      |> Enum.filter(&MapSet.member?(subscribed, &1))
      |> queue_followed()
    end

    :ok
  end

  defp subscribed(user_ids) do
    Repo.all(
      from s in Subscription, where: s.user_id in ^user_ids, distinct: true, select: s.user_id
    )
    |> MapSet.new()
  end

  defp queue_followed([]), do: :ok

  defp queue_followed(user_ids) do
    sent =
      Repo.all(
        from p in Preference,
          where: p.user_id in ^user_ids,
          select: {p.user_id, p.followed_sent_at}
      )
      |> Map.new()

    for user_id <- user_ids do
      Oban.insert!(
        FollowedWorker.new(%{"user_id" => user_id}, scheduled_at: followed_due(sent[user_id]))
      )
    end

    :ok
  end

  @doc """
  When the next followed-activity push (PN-04) may go, after one sent at `sent_at` (nil:
  never): `push_followed_interval_minutes` later, or now when that has passed.
  """
  @spec followed_due(DateTime.t() | nil, DateTime.t()) :: DateTime.t()
  def followed_due(sent_at, now \\ DateTime.utc_now())
  def followed_due(nil, now), do: now

  def followed_due(%DateTime{} = sent_at, now) do
    due = DateTime.add(sent_at, Settings.get(:push_followed_interval_minutes), :minute)
    if DateTime.after?(due, now), do: due, else: now
  end

  @doc """
  Whether a push of `kind` about `topic` may reach `user` (PN-09): one check for notification
  levels and quiet hours. Until NO-03 is built, a muted topic is "none" (nothing) and every
  other topic "all".
  """
  @spec allowed?(User.t(), Topic.t(), String.t()) :: boolean()
  def allowed?(%User{id: user_id}, %Topic{id: topic_id}, _kind) do
    not Repo.exists?(
      from f in Follow, where: f.user_id == ^user_id and f.topic_id == ^topic_id and f.muted
    )
  end

  @banner_quiet_days 14

  @doc """
  Whether the notifications banner (PN-20) is offered to `user` on category and topic pages:
  push on (PN-19); the welcome card seen (`welcomed_at`: never on the first page view after
  sign-up); "Not now" not said in the last #{@banner_quiet_days} days; and the user has
  posted or follows a topic. The browser decides the rest (`assets/js/push_banner.js`:
  permission still undecided, push supported, or an iPhone or iPad Safari tab).
  """
  @spec banner?(User.t() | nil) :: boolean()
  def banner?(nil), do: false

  def banner?(%User{} = user) do
    enabled?() and user.welcomed_at != nil and not dismissed_recently?(user) and
      (Repo.exists?(from m in Idejo.Messages.Message, where: m.author_id == ^user.id) or
         Repo.exists?(from f in Follow, where: f.user_id == ^user.id and f.following))
  end

  defp dismissed_recently?(user) do
    case preferences(user).banner_dismissed_at do
      nil -> false
      at -> DateTime.diff(DateTime.utc_now(), at, :day) < @banner_quiet_days
    end
  end

  @doc "Records \"Not now\" on the notifications banner (PN-21): hidden for #{@banner_quiet_days} days."
  @spec dismiss_banner(User.t()) :: {:ok, Preference.t()} | {:error, Ecto.Changeset.t()}
  def dismiss_banner(%User{} = user) do
    user
    |> preferences()
    |> Ecto.Changeset.change(banner_dismissed_at: DateTime.utc_now())
    |> Repo.insert_or_update()
  end

  @doc "The user's push types (PN-11): their row, or the defaults (all on)."
  @spec preferences(User.t()) :: Preference.t()
  def preferences(%User{id: id}),
    do: Repo.get(Preference, id) || %Preference{user_id: id}

  @doc "A changeset for the user's push types."
  @spec change_preferences(User.t(), map()) :: Ecto.Changeset.t()
  def change_preferences(%User{} = user, attrs \\ %{}),
    do: Preference.changeset(preferences(user), attrs)

  @doc "Saves the user's push types (PN-11), for all their browsers."
  @spec update_preferences(User.t(), map()) ::
          {:ok, Preference.t()} | {:error, Ecto.Changeset.t()}
  def update_preferences(%User{} = user, attrs),
    do: user |> change_preferences(attrs) |> Repo.insert_or_update()

  @doc "Whether the user takes pushes of `kind` (PN-11)."
  @spec wants?(Preference.t(), String.t()) :: boolean()
  def wants?(%Preference{} = preference, "reply"), do: preference.reply
  def wants?(%Preference{} = preference, "mention"), do: preference.mention
  def wants?(%Preference{} = preference, "role_mention"), do: preference.role_mention
  def wants?(%Preference{} = preference, "follow"), do: preference.followed

  @doc "Deletes `user`'s subscription with `endpoint`, if there is one."
  @spec unsubscribe(User.t(), String.t()) :: :ok
  def unsubscribe(%User{id: user_id}, endpoint) when is_binary(endpoint) do
    Repo.delete_all(
      from s in Subscription, where: s.user_id == ^user_id and s.endpoint == ^endpoint
    )

    :ok
  end

  @doc "The user's subscriptions, newest first."
  @spec list_subscriptions(User.t()) :: [Subscription.t()]
  def list_subscriptions(%User{id: user_id}) do
    Repo.all(from s in Subscription, where: s.user_id == ^user_id, order_by: [desc: s.created_at])
  end

  @doc "Deletes the subscriptions made in the sign-in sessions `session_ids` (they ended)."
  @spec delete_for_sessions([String.t()]) :: :ok
  def delete_for_sessions([]), do: :ok

  def delete_for_sessions(session_ids) when is_list(session_ids) do
    Repo.delete_all(from s in Subscription, where: s.session_id in ^session_ids)
    :ok
  end

  @doc "Deletes every subscription of `user` (all their sessions ended)."
  @spec delete_for_user(User.t()) :: :ok
  def delete_for_user(%User{id: user_id}) do
    Repo.delete_all(from s in Subscription, where: s.user_id == ^user_id)
    :ok
  end

  @doc "Deletes every subscription on the server (the VAPID keys were rotated, PN-14)."
  @spec delete_all() :: non_neg_integer()
  def delete_all do
    {count, _} = Repo.delete_all(Subscription)
    count
  end
end

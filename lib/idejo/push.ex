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

  Changes to this module get an extra careful human review (DV-06).
  """
  import Ecto.Query

  alias Idejo.Accounts.User
  alias Idejo.Push.{Endpoint, Subscription}
  alias Idejo.RateLimit
  alias Idejo.Repo
  alias Idejo.Settings

  @max_per_user 10

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

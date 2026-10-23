# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Notifications.Digest do
  @moduledoc """
  The email summary (steward decision, 2026-10-23, with NO-04 of the v1 sheet): a member who
  has not been seen for 24 hours (`users.last_seen_at`, kept by `IdejoWeb.UserAuth`) gets one
  email counting what happened since, as they chose in their profile
  (`Idejo.Notifications.EmailPreference`): mentions and replies, +role mentions, new
  messages in topics they started or follow, new topics, any activity. Nothing to count, no
  email.

  Only finished messages count (closed since then, NO-04), not deleted, by others, in
  categories they may view and topics they did not mute. With "once a week" (the default)
  they get no second summary for seven days while they stay away, and the email says so;
  without it, one a day. Coming back starts again. Every email has a one-click unsubscribe
  link (`unsubscribe/1`, `List-Unsubscribe`), and says where the profile turns it off.

  `Idejo.Notifications.DigestWorker` runs `run/1` every hour.
  """
  import Ecto.Query
  import Swoosh.Email, except: [from: 2]
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Topic}
  alias Idejo.Mailer
  alias Idejo.Messages.Message
  alias Idejo.Notifications.{EmailPreference, Notification}
  alias Idejo.Reading
  alias Idejo.Repo
  alias Idejo.Settings

  @away_hours 24
  @week_days 7

  @doc "The user's choices; the defaults when they never changed them."
  @spec preferences(User.t()) :: EmailPreference.t()
  def preferences(%User{id: id}),
    do: Repo.get(EmailPreference, id) || %EmailPreference{user_id: id}

  @doc "A changeset of the user's choices, for the profile's form."
  @spec change_preferences(User.t(), map()) :: Ecto.Changeset.t()
  def change_preferences(%User{} = user, attrs \\ %{}),
    do: EmailPreference.changeset(preferences(user), attrs)

  @doc "Saves the user's choices."
  @spec update_preferences(User.t(), map()) ::
          {:ok, EmailPreference.t()} | {:error, Ecto.Changeset.t()}
  def update_preferences(%User{} = user, attrs) do
    user |> change_preferences(attrs) |> Repo.insert_or_update()
  end

  @doc """
  Turns every summary off for the owner of an unsubscribe token (the email's one-click
  link, NO-04). `:error` for an unknown token.
  """
  @spec unsubscribe(String.t()) :: :ok | :error
  def unsubscribe(token) when is_binary(token) do
    off = Keyword.new(EmailPreference.options(), &{&1, false})

    case Repo.update_all(from(p in EmailPreference, where: p.unsubscribe_token == ^token),
           set: off
         ) do
      {1, _} -> :ok
      _ -> :error
    end
  end

  @doc "Sends the summaries due at `now`; returns how many were sent."
  @spec run(DateTime.t()) :: non_neg_integer()
  def run(now \\ DateTime.utc_now()) do
    now
    |> due_users()
    |> Enum.count(&(send_digest(&1, now) == :sent))
  end

  # Active, verified members away for a day, who chose something, and who had no summary
  # since they were last seen (or, still away, none for a week, or a day without "once a
  # week").
  defp due_users(now) do
    away = DateTime.add(now, -@away_hours, :hour)
    week = DateTime.add(now, -@week_days, :day)

    from(u in User,
      as: :user,
      left_join: p in EmailPreference,
      as: :preference,
      on: p.user_id == u.id,
      where: u.status == "active" and not is_nil(u.confirmed_at),
      where: coalesce(u.last_seen_at, u.created_at) <= ^away,
      select: u
    )
    |> chose_something()
    |> not_sent_lately(away, week)
    |> Repo.all()
    |> Enum.reject(&Accounts.banned?(&1, now))
  end

  # At least one option on (no row: the defaults, two of them on).
  defp chose_something(query) do
    where(
      query,
      [preference: p],
      coalesce(p.mentions, true) or coalesce(p.own_topics, true) or p.role_mentions or
        p.followed_topics or p.new_topics or p.all_activity
    )
  end

  # No summary yet, or none since they were last seen, or none for a week (a day without
  # "once a week").
  defp not_sent_lately(query, away, week) do
    where(
      query,
      [user: u, preference: p],
      is_nil(p.digest_sent_at) or p.digest_sent_at < coalesce(u.last_seen_at, u.created_at) or
        (coalesce(p.once_a_week, true) and p.digest_sent_at <= ^week) or
        (not coalesce(p.once_a_week, true) and p.digest_sent_at <= ^away)
    )
  end

  defp send_digest(user, now) do
    preference = preferences(user)
    since = since(user, preference)
    counts = counts(user, preference, since, now)

    if Enum.any?(counts, fn {_kind, count} -> count > 0 end) do
      preference = with_token(preference)
      {:ok, _} = deliver(user, preference, counts)

      preference
      |> Ecto.Changeset.change(digest_sent_at: now)
      |> Repo.insert_or_update!()

      :sent
    else
      :nothing
    end
  end

  # What is new: since they were last seen, or since the last summary of this absence.
  defp since(user, %{digest_sent_at: sent}) do
    seen = user.last_seen_at || user.created_at
    if sent && DateTime.after?(sent, seen), do: sent, else: seen
  end

  defp with_token(%EmailPreference{unsubscribe_token: nil} = preference) do
    token = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

    preference
    |> Ecto.Changeset.change(unsubscribe_token: token)
    |> Repo.insert_or_update!()
  end

  defp with_token(preference), do: preference

  @doc """
  What the summary counts for the user between `since` and `now`, for the options they
  chose, in the profile's order: `[{option, count}]`.
  """
  @spec counts(User.t(), EmailPreference.t(), DateTime.t(), DateTime.t()) :: [{atom(), integer()}]
  def counts(%User{} = user, %EmailPreference{} = preference, since, now) do
    for option <- EmailPreference.options(),
        Map.fetch!(preference, option),
        do: {option, count(option, user, since, now)}
  end

  # Finished messages by others, since then, where the user may look and did not mute.
  defp messages(user, since, now) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    from m in Message,
      as: :message,
      join: t in Topic,
      as: :topic,
      on: t.id == m.topic_id,
      where: m.state == "closed" and m.closed_at > ^since and m.closed_at <= ^now,
      where: is_nil(m.deleted_at) and m.author_id != ^user.id,
      where: t.category_id in subquery(viewable),
      where: t.id not in subquery(Reading.muted_topic_ids(user.id))
  end

  defp count(:mentions, user, since, now), do: notified(user, since, now, ["mention", "reply"])
  defp count(:role_mentions, user, since, now), do: notified(user, since, now, ["role_mention"])

  defp count(:own_topics, user, since, now),
    do: user |> messages(since, now) |> where([topic: t], t.author_id == ^user.id) |> count_all()

  defp count(:followed_topics, user, since, now) do
    user
    |> messages(since, now)
    |> where([topic: t], t.id in subquery(Reading.followed_topic_ids(user)))
    |> count_all()
  end

  defp count(:new_topics, user, since, now) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    from(t in Topic,
      where: t.created_at > ^since and t.created_at <= ^now and t.author_id != ^user.id,
      where: t.category_id in subquery(viewable) and t.state != "archived"
    )
    |> count_all()
  end

  defp count(:all_activity, user, since, now), do: user |> messages(since, now) |> count_all()

  defp notified(user, since, now, kinds) do
    user
    |> messages(since, now)
    |> join(:inner, [message: m], n in Notification,
      on: n.message_id == m.id and n.user_id == ^user.id and n.kind in ^kinds
    )
    |> count_all()
  end

  defp count_all(query), do: query |> exclude(:select) |> select([q], count()) |> Repo.one()

  defp deliver(user, preference, counts) do
    base = Application.fetch_env!(:idejo, :base_uri)
    unsubscribe = "#{base}/email/unsubscribe/#{preference.unsubscribe_token}"
    server = Settings.get(:server_name)

    email =
      new()
      |> to(user.email)
      |> Swoosh.Email.from({server, Settings.get(:mail_from)})
      |> subject(gettext("What you missed on %{server}", server: server))
      |> header("List-Unsubscribe", "<#{unsubscribe}>")
      |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
      |> text_body(body(user, preference, counts, base, unsubscribe, server))

    Mailer.deliver_email(email)
  end

  defp body(user, preference, counts, base, unsubscribe, server) do
    lines =
      for {option, count} <- counts, count > 0, do: "- " <> line(option, count)

    week =
      if preference.once_a_week,
        do:
          gettext(
            "This is your last summary this week: if you stay away, the next one comes in a week."
          ) <> "\n\n",
        else: ""

    gettext(
      """
      Hi %{name},

      While you were away from %{server}, there was:

      %{lines}

      See what is new: %{unread}

      %{week}You can turn these emails off in your profile: open the menu under your name, then Profile and account, Email notifications (%{settings}).
      Or stop them all with one click: %{unsubscribe}
      """,
      name: user.display_name,
      server: server,
      lines: Enum.join(lines, "\n"),
      unread: base <> "/unread",
      week: week,
      settings: base <> "/users/settings",
      unsubscribe: unsubscribe
    )
  end

  defp line(:mentions, n),
    do:
      ngettext(
        "%{count} mention of you or reply to your messages",
        "%{count} mentions of you and replies to your messages",
        n
      )

  defp line(:role_mentions, n),
    do: ngettext("%{count} mention of one of your roles", "%{count} mentions of your roles", n)

  defp line(:own_topics, n),
    do:
      ngettext(
        "%{count} new message in topics you started",
        "%{count} new messages in topics you started",
        n
      )

  defp line(:followed_topics, n),
    do:
      ngettext(
        "%{count} new message in topics you follow",
        "%{count} new messages in topics you follow",
        n
      )

  defp line(:new_topics, n), do: ngettext("%{count} new topic", "%{count} new topics", n)

  defp line(:all_activity, n),
    do: ngettext("%{count} new message in the forum", "%{count} new messages in the forum", n)
end

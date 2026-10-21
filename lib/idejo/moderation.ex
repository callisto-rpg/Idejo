# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Moderation do
  @moduledoc """
  Moderation (MO): reports (MO-01) and the moderation log (MO-03).

  Members report a message with a reason; the moderators of its category (owners and
  administrators everywhere, steward decision) see the open reports grouped by message, and
  resolve or dismiss them all at once, which is logged.

  Every moderator action records one log entry, with the moderator, the target (a message,
  topic or user), the reason and the time.

  Call `record/4` inside the same transaction as the action, so an action is never taken
  without its entry. The log is append-only: the database refuses updates and deletes.

  Who sees it: owners and administrators see every entry; a moderator sees the entries about
  the categories they may moderate (the `:moderate` right), and server moderators the
  server-wide ones too (bans).
  """
  import Ecto.Query, warn: false

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Topic}
  alias Idejo.Messages.Message
  alias Idejo.Moderation.{Action, Report}
  alias Idejo.RateLimit
  alias Idejo.Repo

  @doc """
  Records an action by `moderator` on `target`, e.g. `"message.close"`.

  ## Options

    * `:reason` - why, in the moderator's words (shown in the log).
    * `:details` - a JSON-ready map of what changed, e.g. a topic's old and new category.
  """
  @spec record(User.t(), String.t(), Message.t() | Topic.t() | User.t(), keyword()) ::
          {:ok, Action.t()} | {:error, Ecto.Changeset.t()}
  def record(%User{} = moderator, action, target, opts \\ []) do
    {type, category_id} = target_of(target)

    Repo.insert(%Action{
      moderator_id: moderator.id,
      action: action,
      target_type: type,
      target_id: target.id,
      category_id: category_id,
      reason: blank_to_nil(opts[:reason]),
      details: Keyword.get(opts, :details, %{})
    })
  end

  defp target_of(%Message{topic_id: topic_id}),
    do: {"message", Repo.one!(from t in Topic, where: t.id == ^topic_id, select: t.category_id)}

  defp target_of(%Topic{category_id: category_id}), do: {"topic", category_id}
  defp target_of(%User{}), do: {"user", nil}

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(reason) do
    case String.trim(reason) do
      "" -> nil
      reason -> reason
    end
  end

  ## Reports (MO-01)

  @doc "A changeset for the report form."
  @spec change_report(map()) :: Ecto.Changeset.t()
  def change_report(attrs \\ %{}), do: Report.changeset(%Report{}, attrs)

  @doc """
  Reports a message, as `user`, with a reason: a message they may view and did not write
  (`{:error, :forbidden}` otherwise). Once per open report: a second gets an error on the
  changeset.
  """
  @spec report_message(User.t(), Message.t(), map()) ::
          {:ok, Report.t()} | {:error, :forbidden | :rate_limited | Ecto.Changeset.t()}
  def report_message(%User{} = user, %Message{} = message, attrs) do
    cond do
      message.author_id == user.id or message.deleted_at != nil ->
        {:error, :forbidden}

      is_nil(Idejo.Forum.get_viewable_message(user, message.id)) ->
        {:error, :forbidden}

      RateLimit.check(:report, user.id) != :ok ->
        {:error, :rate_limited}

      true ->
        %Report{message_id: message.id, reporter_id: user.id}
        |> Report.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc """
  The open reports the moderator may handle, grouped by message, the longest waiting first:
  `[%{message: message, reports: [report]}]`, with the message's author and topic and each
  report's reporter.
  """
  @spec list_open_reports(User.t()) :: [%{message: Message.t(), reports: [Report.t()]}]
  def list_open_reports(%User{} = moderator) do
    moderator
    |> open_reports()
    |> order_by([r], asc: r.created_at, asc: r.id)
    |> preload([:reporter, message: [:author, :topic]])
    |> Repo.all()
    |> Enum.group_by(& &1.message_id)
    |> Enum.map(fn {_id, [first | _] = reports} ->
      %{message: first.message, reports: reports}
    end)
    |> Enum.sort_by(fn %{reports: [first | _]} -> first.created_at end, DateTime)
  end

  @doc "How many messages have open reports the moderator may handle."
  @spec open_report_count(User.t() | nil) :: non_neg_integer()
  def open_report_count(nil), do: 0

  def open_report_count(%User{} = moderator) do
    moderator
    |> open_reports()
    |> select([r], count(r.message_id, :distinct))
    |> Repo.one()
  end

  defp open_reports(moderator) do
    query =
      from r in Report,
        join: m in assoc(r, :message),
        join: t in Topic,
        on: t.id == m.topic_id,
        where: r.status == "open"

    if Access.administrator?(moderator) do
      query
    else
      moderated = Category |> Access.where_allowed(moderator, :moderate) |> select([c], c.id)
      where(query, [_r, _m, t], t.category_id in subquery(moderated))
    end
  end

  @doc """
  Resolves or dismisses every open report of a message, as a moderator of its category, with
  an optional note; logged as `report.resolve` or `report.dismiss` (MO-03).
  """
  @spec handle_reports(User.t(), Message.t(), :resolve | :dismiss, String.t() | nil) ::
          {:ok, non_neg_integer()} | {:error, :forbidden | :no_reports}
  def handle_reports(%User{} = moderator, %Message{} = message, outcome, note \\ nil)
      when outcome in [:resolve, :dismiss] do
    category =
      Repo.one!(
        from t in Topic,
          join: c in assoc(t, :category),
          where: t.id == ^message.topic_id,
          select: c
      )

    if Access.can?(moderator, :moderate, category) do
      Repo.transact(fn -> close_reports(moderator, message, outcome, note) end)
    else
      {:error, :forbidden}
    end
  end

  defp close_reports(moderator, message, outcome, note) do
    status = if outcome == :resolve, do: "resolved", else: "dismissed"

    {count, _} =
      Repo.update_all(
        from(r in Report, where: r.message_id == ^message.id and r.status == "open"),
        set: [status: status, handled_by_id: moderator.id, handled_at: DateTime.utc_now()]
      )

    if count == 0 do
      {:error, :no_reports}
    else
      with {:ok, _} <-
             record(moderator, "report.#{outcome}", message,
               reason: note,
               details: %{"reports" => count}
             ) do
        {:ok, count}
      end
    end
  end

  @doc """
  Marks a message's open reports resolved by `moderator`, inside the caller's transaction:
  when the message is deleted (MO-02), which answers them.
  """
  @spec resolve_reports_of(User.t(), Message.t()) :: {non_neg_integer(), nil}
  def resolve_reports_of(%User{} = moderator, %Message{id: id}) do
    Repo.update_all(
      from(r in Report, where: r.message_id == ^id and r.status == "open"),
      set: [status: "resolved", handled_by_id: moderator.id, handled_at: DateTime.utc_now()]
    )
  end

  @doc """
  Returns true when the user may moderate somewhere: a server moderator (owners and
  administrators included, `Access.server_moderator?/1`), or the `:moderate` right in at least
  one category.
  """
  @spec moderator?(User.t() | nil) :: boolean()
  def moderator?(nil), do: false

  def moderator?(%User{} = user) do
    Access.server_moderator?(user) or
      Category |> Access.where_allowed(user, :moderate) |> Repo.exists?()
  end

  @doc """
  The log entries the user may see, newest first, 30 a page: `{entries, more?}`, each with its
  moderator.
  """
  @spec list(User.t(), keyword()) :: {[Action.t()], boolean()}
  def list(%User{} = user, opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 30)
    page = max(Keyword.get(opts, :page, 1), 1)

    rows =
      from(a in Action,
        order_by: [desc: a.created_at, desc: a.id],
        offset: ^((page - 1) * per_page),
        limit: ^(per_page + 1),
        preload: [:moderator]
      )
      |> visible_to(user)
      |> Repo.all()

    {Enum.take(rows, per_page), length(rows) > per_page}
  end

  # Server-wide entries (bans, MO-02) have no category: server moderators see them.
  defp visible_to(query, user) do
    cond do
      Access.administrator?(user) ->
        query

      Access.server_moderator?(user) ->
        moderated = Category |> Access.where_allowed(user, :moderate) |> select([c], c.id)
        where(query, [a], is_nil(a.category_id) or a.category_id in subquery(moderated))

      true ->
        moderated = Category |> Access.where_allowed(user, :moderate) |> select([c], c.id)
        where(query, [a], a.category_id in subquery(moderated))
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Moderation do
  @moduledoc """
  Moderation (MO). This module holds the moderation log (MO-03): every moderator action
  records one entry, with the moderator, the target (a message, topic or user), the reason
  and the time.

  Call `record/4` inside the same transaction as the action, so an action is never taken
  without its entry. The log is append-only: the database refuses updates and deletes.

  Who sees it: owners and administrators see every entry; a moderator sees the entries about
  the categories they may moderate (the `:moderate` right).
  """
  import Ecto.Query, warn: false

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Topic}
  alias Idejo.Messages.Message
  alias Idejo.Moderation.Action
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

  @doc """
  Returns true when the user may moderate somewhere: an owner or administrator, or the
  `:moderate` right in at least one category.
  """
  @spec moderator?(User.t() | nil) :: boolean()
  def moderator?(nil), do: false

  def moderator?(%User{} = user) do
    Access.administrator?(user) or
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

  defp visible_to(query, user) do
    if Access.administrator?(user) do
      query
    else
      moderated = Category |> Access.where_allowed(user, :moderate) |> select([c], c.id)
      where(query, [a], a.category_id in subquery(moderated))
    end
  end
end

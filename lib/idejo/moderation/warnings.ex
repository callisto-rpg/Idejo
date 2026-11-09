# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Moderation.Warnings do
  @moduledoc """
  Warnings (MO-02 "warn"; steward request, 2026-11-09). A moderator of a message's category
  warns its author with a reason (`warn/3`): stored, logged as `user.warn` against the author
  in that category (MO-03), then sent to the author live (`{:warning, warning}` on
  `"user:{id}"`, a bubble and a card) and as a push. Until they acknowledge it
  (`acknowledge/1`), every page they open shows it in a card: `users.warning_pending` says
  one waits, so other pages ask nothing.

  Never the moderator themselves, an owner or administrator, or an account that is not
  active; never a deleted message's author through it, nor in a private conversation (no
  category to moderate). Moderators see the warnings given in the categories they moderate
  (`visible/2`); owners and administrators all of them.
  """
  use Gettext, backend: IdejoWeb.Gettext

  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Federation
  alias Idejo.Forum.{Category, Topic}
  alias Idejo.Messages.Message
  alias Idejo.Moderation
  alias Idejo.Moderation.Warning
  alias Idejo.Push
  alias Idejo.Repo

  @max_reason 1000

  @doc "The longest reason, in characters."
  @spec max_reason() :: pos_integer()
  def max_reason, do: @max_reason

  @doc """
  The author `moderator` may warn for `message`, or why not: `:forbidden` (not a moderator of
  its category, a private conversation, a deleted message), `:not_warnable` (themselves, an
  owner or administrator, an account not active).
  """
  @spec warnable(User.t(), Message.t()) :: {:ok, User.t()} | {:error, :forbidden | :not_warnable}
  def warnable(%User{} = moderator, %Message{} = message) do
    topic = Repo.get!(Topic, message.topic_id)

    with :ok <- moderates(moderator, topic, message) do
      author(moderator, message.author_id && Repo.get(User, message.author_id))
    end
  end

  defp moderates(moderator, topic, message) do
    if topic.private or is_nil(topic.category_id) or message.deleted_at != nil or
         not Access.can?(moderator, :moderate, %Category{id: topic.category_id}),
       do: {:error, :forbidden},
       else: :ok
  end

  defp author(moderator, %User{status: "active"} = author) do
    if author.id == moderator.id or Access.administrator?(author),
      do: {:error, :not_warnable},
      else: {:ok, author}
  end

  defp author(_moderator, _author), do: {:error, :not_warnable}

  @doc """
  Warns `message`'s author, as `moderator`, with `reason` (required, at most
  #{@max_reason} characters). Then tells them: live, and by push.
  """
  @spec warn(User.t(), Message.t(), String.t()) ::
          {:ok, Warning.t()} | {:error, :forbidden | :not_warnable | :reason}
  def warn(%User{} = moderator, %Message{} = message, reason) when is_binary(reason) do
    reason = String.trim(reason)

    with :ok <- check_reason(reason),
         {:ok, author} <- warnable(moderator, message),
         {:ok, warning} <- Repo.transact(fn -> save(moderator, author, message, reason) end) do
      tell(author, warning)
      {:ok, warning}
    end
  end

  def warn(_moderator, _message, _reason), do: {:error, :reason}

  defp check_reason(reason) do
    if reason != "" and String.length(reason) <= @max_reason, do: :ok, else: {:error, :reason}
  end

  defp save(moderator, author, message, reason) do
    category_id =
      Repo.one!(from t in Topic, where: t.id == ^message.topic_id, select: t.category_id)

    warning = %Warning{
      id: Federation.generate_id(),
      user_id: author.id,
      moderator_id: moderator.id,
      message_id: message.id,
      category_id: category_id,
      reason: reason
    }

    with {:ok, warning} <- Repo.insert(warning),
         {1, _} <-
           Repo.update_all(from(u in User, where: u.id == ^author.id),
             set: [warning_pending: true]
           ),
         {:ok, _} <-
           Moderation.record(moderator, "user.warn", author,
             reason: reason,
             category_id: category_id,
             details: %{"message_id" => message.id}
           ) do
      {:ok, warning}
    end
  end

  # Live (a bubble and the card on any page open), and as a push to their browsers.
  defp tell(author, warning) do
    Phoenix.PubSub.broadcast(Idejo.PubSub, "user:" <> author.id, {:warning, warning})

    _ =
      Push.deliver(
        author,
        %{
          "web_push" => 8030,
          "notification" => %{
            "title" => gettext("A moderator warned you"),
            "body" => String.slice(warning.reason, 0, 120),
            "navigate" => Application.fetch_env!(:idejo, :base_uri) <> "/",
            "tag" => "warning",
            "lang" => Gettext.get_locale(IdejoWeb.Gettext)
          }
        },
        urgency: "high"
      )

    :ok
  end

  @doc "The warnings `user` has not acknowledged, oldest first; none without asking unless one waits."
  @spec pending(User.t() | nil) :: [Warning.t()]
  def pending(%User{warning_pending: true, id: id}) do
    Repo.all(
      from w in Warning,
        where: w.user_id == ^id and is_nil(w.seen_at),
        order_by: [asc: w.created_at, asc: w.id]
    )
  end

  def pending(_user), do: []

  @doc "Marks every warning of `user` seen: the card goes."
  @spec acknowledge(User.t()) :: :ok
  def acknowledge(%User{id: id}) do
    now = DateTime.utc_now(:second)

    Repo.transact(fn ->
      Repo.update_all(from(w in Warning, where: w.user_id == ^id and is_nil(w.seen_at)),
        set: [seen_at: now]
      )

      Repo.update_all(from(u in User, where: u.id == ^id), set: [warning_pending: false])
      {:ok, :done}
    end)

    :ok
  end

  @doc """
  `user`'s warnings `moderator` may see, newest first, with their moderator and message:
  all for owners and administrators, else those given in categories they moderate.
  """
  @spec visible(User.t(), User.t()) :: [Warning.t()]
  def visible(%User{} = moderator, %User{id: user_id}) do
    from(w in Warning,
      where: w.user_id == ^user_id,
      order_by: [desc: w.created_at, desc: w.id],
      preload: [:moderator]
    )
    |> seen_by(moderator)
    |> Repo.all()
  end

  @doc "How many of `user`'s warnings `moderator` may see (`visible/2`)."
  @spec count_visible(User.t(), User.t()) :: non_neg_integer()
  def count_visible(%User{} = moderator, %User{id: user_id}) do
    from(w in Warning, where: w.user_id == ^user_id)
    |> seen_by(moderator)
    |> Repo.aggregate(:count)
  end

  defp seen_by(query, moderator) do
    if Access.administrator?(moderator) do
      query
    else
      moderated = Category |> Access.where_allowed(moderator, :moderate) |> select([c], c.id)
      where(query, [w], w.category_id in subquery(moderated))
    end
  end
end

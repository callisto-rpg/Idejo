# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum do
  @moduledoc """
  The forum structure: categories (RP-03) and topics (TP-01), with their tags (TP-19,
  `Idejo.Forum.Tags`).

  Administrators create, rename, reorder and delete categories in **Admin → Categories**. Each
  change is audited (SP-06) and recorded as an activity (FD-02) in the same transaction.
  """

  import Ecto.Query, warn: false

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Federation
  alias Idejo.Forum.{Category, Tags, Topic}
  alias Idejo.Messages
  alias Idejo.Messages.Message
  alias Idejo.Moderation
  alias Idejo.RateLimit
  alias Idejo.Repo

  @doc """
  Lists the categories in their order.
  """
  @spec list_categories() :: [Category.t()]
  def list_categories do
    Repo.all(from c in Category, order_by: [asc: c.position, asc: c.name])
  end

  @doc """
  Gets a category by slug, or `nil`.
  """
  @spec get_category_by_slug(String.t()) :: Category.t() | nil
  def get_category_by_slug(slug) when is_binary(slug), do: Repo.get_by(Category, slug: slug)

  @doc """
  Lists, in their order, the categories the visitor (`nil`) or user may view (AC-05).
  Filtered in the query by `Idejo.Access.where_allowed/3`.
  """
  @spec list_viewable_categories(User.t() | nil) :: [Category.t()]
  def list_viewable_categories(user) do
    from(c in Category, order_by: [asc: c.position, asc: c.name])
    |> Access.where_allowed(user, :view)
    |> Repo.all()
  end

  @doc """
  Lists, in their order, the categories the visitor (`nil`) or user may view, each with its
  topic count and last activity (`nil` without topics), as the home page shows them (MVP §5).
  """
  @spec list_category_summaries(User.t() | nil) :: [
          %{category: Category.t(), topics: non_neg_integer(), last_activity_at: DateTime.t()}
        ]
  def list_category_summaries(user) do
    stats =
      from t in Topic,
        group_by: t.category_id,
        select: %{category_id: t.category_id, topics: count(), last: max(t.last_activity_at)}

    from(c in Category, order_by: [asc: c.position, asc: c.name])
    |> Access.where_allowed(user, :view)
    |> join(:left, [category: c], s in subquery(stats), on: s.category_id == c.id)
    |> select([category: c], %{category: c})
    |> select_merge([_c, s], %{topics: coalesce(s.topics, 0), last_activity_at: s.last})
    |> Repo.all()
  end

  @doc """
  Lists the most recently active topics the visitor (`nil`) or user may view, across
  categories, with their category: at most `limit`. Archived topics are left out.
  """
  @spec list_active_topics(User.t() | nil, pos_integer()) :: [Topic.t()]
  def list_active_topics(user, limit \\ 10) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    Repo.all(
      from t in Topic,
        where: t.category_id in subquery(viewable) and t.state != "archived",
        order_by: [desc: t.last_activity_at, desc: t.id],
        limit: ^limit,
        preload: [:category, tags: ^Tags.ordered()]
    )
  end

  @doc """
  Gets a category by slug if the visitor (`nil`) or user may view it, or `nil` (AC-05).
  """
  @spec get_viewable_category(User.t() | nil, String.t()) :: Category.t() | nil
  def get_viewable_category(user, slug) when is_binary(slug) do
    from(c in Category, where: c.slug == ^slug)
    |> Access.where_allowed(user, :view)
    |> Repo.one()
  end

  @doc """
  Returns a changeset for the new-category form.
  """
  def change_new_category(attrs \\ %{}), do: Category.create_changeset(%Category{}, attrs)

  @doc """
  Returns a changeset for the edit form.
  """
  def change_category(%Category{} = category, attrs \\ %{}),
    do: Category.update_changeset(category, attrs)

  @doc """
  Creates a category at the end of the order, as `admin`.

  Without a slug, one is made from the name ("Help & Support" becomes `help-support`, with
  `-2`, `-3`… added when taken). Audited as `category.create`, with a `create` activity.
  """
  @spec create_category(User.t(), map()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def create_category(%User{} = admin, attrs) do
    id = Federation.generate_id()

    Repo.transact(fn ->
      lock_categories()
      position = Repo.aggregate(Category, :count)

      attrs =
        attrs |> Map.new(fn {key, value} -> {to_string(key), value} end) |> put_default_slug()

      category = %Category{id: id, uri: Federation.uri(:category, id), position: position}

      with {:ok, category} <- Repo.insert(Category.create_changeset(category, attrs)),
           :ok <- record(admin, "create", nil, category) do
        {:ok, category}
      end
    end)
  end

  @doc """
  Renames a category or changes its description, as `admin`. The slug stays, so links keep
  working. Audited as `category.update`, with an `update` activity. Unchanged values write
  nothing.
  """
  @spec update_category(User.t(), Category.t(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def update_category(%User{} = admin, %Category{} = category, attrs) do
    case Category.update_changeset(category, attrs) do
      %Ecto.Changeset{changes: changes} when changes == %{} -> {:ok, category}
      changeset -> Repo.transact(fn -> save_category(admin, category, changeset) end)
    end
  end

  defp save_category(admin, category, changeset) do
    with {:ok, updated} <- Repo.update(changeset),
         :ok <- record(admin, "update", category, updated) do
      {:ok, updated}
    end
  end

  @doc """
  Moves a category one place up or down, as `admin`. Audited as `category.reorder` with the
  whole order before and after. Returns `{:error, :at_edge}` at the top or bottom.
  """
  @spec move_category(User.t(), Category.t(), :up | :down) ::
          {:ok, [Category.t()]} | {:error, :at_edge}
  def move_category(%User{} = admin, %Category{} = category, direction)
      when direction in [:up, :down] do
    Repo.transact(fn ->
      lock_categories()
      categories = list_categories()

      case neighbours(categories, category, direction) do
        {category, neighbour} -> swap(admin, categories, category, neighbour)
        nil -> {:error, :at_edge}
      end
    end)
  end

  defp neighbours(categories, category, direction) do
    with index when is_integer(index) <- Enum.find_index(categories, &(&1.id == category.id)),
         target = if(direction == :up, do: index - 1, else: index + 1),
         # Enum.at/2 counts negative indexes from the end, so stop at the top first.
         true <- target >= 0,
         %Category{} = neighbour <- Enum.at(categories, target) do
      {Enum.at(categories, index), neighbour}
    else
      _ -> nil
    end
  end

  defp swap(admin, before, category, neighbour) do
    with {:ok, _} <- Repo.update(Ecto.Changeset.change(category, position: neighbour.position)),
         {:ok, _} <- Repo.update(Ecto.Changeset.change(neighbour, position: category.position)),
         after_ = list_categories(),
         {:ok, _} <-
           Audit.record(admin, "category.reorder", %{"order" => slugs(before)}, %{
             "order" => slugs(after_)
           }) do
      {:ok, after_}
    end
  end

  defp slugs(categories), do: Enum.map(categories, & &1.slug)

  @doc """
  Deletes a category, as `admin`; the ones below move up. Audited as `category.delete`, with
  a `delete` activity.

  A category that still has topics needs `topics:` to say where they go (RP-03):

    * `{:move, target}` - to another category, as they are;
    * `:archive` - to the Archive category, archived and read-only (TP-14). The Archive is
      made the first time something is archived (`archive_category/1`).

  Each topic gets an `update` activity with its new category, and the audit entry records
  where the topics went. Without `topics:` the category is kept (`{:error, :has_topics}`).
  The Archive itself is never deleted (`{:error, :archive}`).
  """
  @spec delete_category(User.t(), Category.t(), keyword()) ::
          {:ok, Category.t()} | {:error, :archive | :has_topics | :invalid_target | term()}
  def delete_category(%User{} = admin, %Category{} = category, opts \\ []) do
    result =
      Repo.transact(fn ->
        lock_categories()
        topic_ids = Repo.all(from t in Topic, where: t.category_id == ^category.id, select: t.id)

        with :ok <- check_deletable(category),
             {:ok, moved} <- move_topics_away(admin, category, topic_ids, opts[:topics]),
             closed = close_if_archived(topic_ids, opts[:topics]),
             {:ok, deleted} <- Repo.delete(category),
             {_, _} <-
               Repo.update_all(from(c in Category, where: c.position > ^category.position),
                 inc: [position: -1]
               ),
             :ok <- record(admin, "delete", category, nil, moved) do
          {:ok, {deleted, closed}}
        end
      end)

    with {:ok, {deleted, closed}} <- result do
      Messages.announce_closed(closed)
      {:ok, deleted}
    end
  end

  # Archived topics are read only: their open messages close (GM-12).
  defp close_if_archived(topic_ids, :archive), do: Messages.close_open_in_topics(topic_ids)
  defp close_if_archived(_topic_ids, _where), do: []

  @doc """
  Counts the topics of each category, as a map from category id. For the admin page.
  """
  @spec topic_counts() :: %{Ecto.UUID.t() => non_neg_integer()}
  def topic_counts do
    Repo.all(from t in Topic, group_by: t.category_id, select: {t.category_id, count()})
    |> Map.new()
  end

  defp check_deletable(%Category{archive: true}), do: {:error, :archive}
  defp check_deletable(%Category{}), do: :ok

  # Returns what the audit entry says about the topics, or nothing when there were none.
  defp move_topics_away(_admin, _category, [], _where), do: {:ok, %{}}
  defp move_topics_away(_admin, _category, _ids, nil), do: {:error, :has_topics}

  defp move_topics_away(admin, category, ids, {:move, %Category{} = target}) do
    target = Repo.get(Category, target.id)

    if target && target.id != category.id && !target.archive do
      move_topics(admin, ids, target, %{})
      # TP-19: the deleted category's own tags go with it; nothing else to drop.
      {:ok, %{"topics" => %{"count" => length(ids), "moved_to" => target.slug}}}
    else
      {:error, :invalid_target}
    end
  end

  defp move_topics_away(admin, _category, ids, :archive) do
    with {:ok, archive} <- archive_category(admin) do
      move_topics(admin, ids, archive, %{state: "archived"})
      {:ok, %{"topics" => %{"count" => length(ids), "archived_in" => archive.slug}}}
    end
  end

  defp move_topics(admin, ids, target, changes) do
    changes = Keyword.new(Map.put(changes, :category_id, target.id))
    {_, topics} = Repo.update_all(from(t in Topic, where: t.id in ^ids, select: t), set: changes)

    for topic <- topics do
      Repo.insert!(
        Federation.activity_changeset(%{
          actor_uri: admin.uri,
          verb: "update",
          object_uri: topic.uri,
          target_uri: target.uri,
          payload: %{"type" => "Page", "name" => topic.title, "state" => topic.state}
        })
      )
    end
  end

  @doc """
  Returns the Archive category (RP-03, TP-14), making it on first use, as `admin`: last in
  the order, named "Archive", and hidden from every role (a `:view` deny each, audited as
  `permission.update`) until an administrator shows it to some in the permission grid.
  Owners and administrators always see it.
  """
  @spec archive_category(User.t()) :: {:ok, Category.t()} | {:error, term()}
  def archive_category(%User{} = admin) do
    case Repo.get_by(Category, archive: true) do
      %Category{} = archive -> {:ok, archive}
      nil -> Repo.transact(fn -> create_archive(admin) end)
    end
  end

  defp create_archive(admin) do
    lock_categories()
    id = Federation.generate_id()

    archive = %Category{
      id: id,
      uri: Federation.uri(:category, id),
      position: Repo.aggregate(Category, :count),
      archive: true
    }

    attrs = %{
      "name" => "Archive",
      "description" => "Topics kept from deleted categories.",
      "slug" => free_slug("archive")
    }

    with {:ok, archive} <- Repo.insert(Category.create_changeset(archive, attrs)),
         :ok <- record(admin, "create", nil, archive),
         :ok <- hide_from_every_role(admin, archive) do
      {:ok, archive}
    end
  end

  defp hide_from_every_role(admin, archive) do
    Access.list_roles()
    |> Enum.reject(&(&1.built_in and &1.name in ~w(owner administrator)))
    |> Enum.reduce_while(:ok, fn role, :ok ->
      case Access.set_permission(admin, role, archive, :view, :deny) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  ## Moderating topics (TP-14)

  @doc """
  Locks, unlocks, pins or unpins a topic, as a moderator (TP-14): someone with the
  `:moderate` right in its category (`{:error, :forbidden}` otherwise).

  A locked topic takes no new messages, and locking closes its open messages (GM-12). Pinned
  topics come first in their category. Archived topics are neither locked nor unlocked
  (`{:error, :archived}`). Each change records a moderation log entry (MO-03) with the
  optional reason and an `update` activity (FD-02) in one transaction; then the topic's
  viewers get `{:topic_changed, topic_id}`. A change to what already is does nothing.
  """
  @spec moderate_topic(User.t(), Topic.t(), :lock | :unlock | :pin | :unpin, String.t() | nil) ::
          {:ok, Topic.t()} | {:error, :forbidden | :archived | Ecto.Changeset.t()}
  def moderate_topic(%User{} = moderator, %Topic{} = topic, action, reason \\ nil)
      when action in [:lock, :unlock, :pin, :unpin] do
    result =
      Repo.transact(fn ->
        topic =
          Repo.one!(from t in Topic, where: t.id == ^topic.id, lock: "FOR UPDATE")
          |> Repo.preload(:category)

        cond do
          not Access.can?(moderator, :moderate, topic.category) -> {:error, :forbidden}
          action in [:lock, :unlock] and topic.state == "archived" -> {:error, :archived}
          true -> apply_moderation(moderator, topic, action, reason)
        end
      end)

    with {:ok, {topic, closed}} <- result do
      Messages.announce_closed(closed)
      Messages.broadcast(topic.id, {:topic_changed, topic.id})
      {:ok, topic}
    end
  end

  defp apply_moderation(moderator, topic, action, reason) do
    changes = moderation_changes(action)

    if Enum.all?(changes, fn {field, value} -> Map.get(topic, field) == value end) do
      {:ok, {topic, []}}
    else
      closed = if action == :lock, do: Messages.close_open_in_topics([topic.id]), else: []

      with {:ok, updated} <- topic |> Ecto.Changeset.change(changes) |> Repo.update(),
           {:ok, _} <- Moderation.record(moderator, "topic.#{action}", updated, reason: reason),
           {:ok, _} <- topic_update_activity(moderator, updated) do
        {:ok, {updated, closed}}
      end
    end
  end

  @doc """
  Moves a topic to another category, as a moderator (TP-15): someone with the `:moderate`
  right in both its category and the target, which is never the Archive
  (`{:error, :forbidden}` / `{:error, :invalid_target}` otherwise). Its messages, open ones
  too, move with it; URIs and links stay (TP-06).

  Logged (MO-03) with the optional reason and the old and new category, with an `update`
  activity, in one transaction; then the topic's viewers get `{:topic_changed, topic_id}`,
  so those who may not view the new category stop seeing it.
  """
  @spec move_topic(User.t(), Topic.t(), Category.t(), String.t() | nil) ::
          {:ok, Topic.t()} | {:error, :forbidden | :invalid_target | Ecto.Changeset.t()}
  def move_topic(%User{} = moderator, %Topic{} = topic, %Category{} = target, reason \\ nil) do
    result =
      Repo.transact(fn ->
        topic =
          Repo.one!(from t in Topic, where: t.id == ^topic.id, lock: "FOR UPDATE")
          |> Repo.preload(:category)

        target = Repo.get(Category, target.id)

        cond do
          not Access.can?(moderator, :moderate, topic.category) ->
            {:error, :forbidden}

          is_nil(target) or target.archive or target.id == topic.category_id ->
            {:error, :invalid_target}

          not Access.can?(moderator, :moderate, target) ->
            {:error, :forbidden}

          true ->
            save_move(moderator, topic, target, reason)
        end
      end)

    with {:ok, topic} <- result, do: Messages.broadcast(topic.id, {:topic_changed, topic.id})
    result
  end

  defp save_move(moderator, topic, target, reason) do
    details = %{
      "from" => %{"id" => topic.category.id, "name" => topic.category.name},
      "to" => %{"id" => target.id, "name" => target.name}
    }

    # Logged under the category it left, where its moderators look for it; `details` has both.
    with {:ok, _} <-
           Moderation.record(moderator, "topic.move", topic, reason: reason, details: details),
         {:ok, moved} <- topic |> Ecto.Changeset.change(category_id: target.id) |> Repo.update(),
         # TP-19: the old category's own tags do not follow the topic.
         _ = Tags.drop_foreign_tags([moved.id], target.id),
         {:ok, _} <- topic_update_activity(moderator, moved) do
      {:ok, %{moved | category: target}}
    end
  end

  @doc """
  The categories a moderator may move the topic to (TP-15): those they moderate, other than
  its own and the Archive, in order.
  """
  @spec list_move_targets(User.t(), Topic.t()) :: [Category.t()]
  def list_move_targets(%User{} = moderator, %Topic{category_id: current}) do
    from(c in Category,
      where: not c.archive and c.id != ^current,
      order_by: [asc: c.position, asc: c.name]
    )
    |> Access.where_allowed(moderator, :moderate)
    |> Repo.all()
  end

  @doc """
  Sets a topic's tags (TP-19), as someone with the `:tag` right in its category (built-in
  moderators by default; `{:error, :forbidden}` otherwise): `tag_ids` among the category's
  available tags (`{:error, :invalid_tags}`), at least one when it has any
  (`{:error, :tag_required}`). Archived topics keep theirs (`{:error, :archived}`).

  Logged (MO-03) as `topic.tags` with the optional reason and the tags before and after, with
  an `update` activity, in one transaction. Choosing the same tags does nothing.
  """
  @spec set_topic_tags(User.t(), Topic.t(), [String.t()], String.t() | nil) ::
          {:ok, Topic.t()}
          | {:error, :forbidden | :archived | :invalid_tags | :tag_required | Ecto.Changeset.t()}
  def set_topic_tags(%User{} = user, %Topic{} = topic, tag_ids, reason \\ nil) do
    Repo.transact(fn ->
      topic =
        Repo.one!(from t in Topic, where: t.id == ^topic.id, lock: "FOR UPDATE")
        |> Repo.preload([:category, tags: Tags.ordered()])

      available = Tags.available_tags(topic.category)
      tag_ids = chosen_ids(tag_ids)
      chosen = Enum.filter(available, &(&1.id in tag_ids))

      cond do
        not Access.can?(user, :tag, topic.category) -> {:error, :forbidden}
        topic.state == "archived" -> {:error, :archived}
        length(chosen) != length(tag_ids) -> {:error, :invalid_tags}
        chosen == [] and available != [] -> {:error, :tag_required}
        Enum.map(chosen, & &1.id) == Enum.map(topic.tags, & &1.id) -> {:ok, topic}
        true -> save_tags(user, topic, chosen, reason)
      end
    end)
  end

  defp save_tags(user, topic, chosen, reason) do
    details = %{"from" => tag_names(topic.tags), "to" => tag_names(chosen)}

    with {:ok, updated} <-
           topic
           |> Ecto.Changeset.change()
           |> Ecto.Changeset.put_assoc(:tags, chosen)
           |> Repo.update(),
         {:ok, _} <-
           Moderation.record(user, "topic.tags", updated, reason: reason, details: details),
         {:ok, _} <- topic_update_activity(user, updated) do
      {:ok, updated}
    end
  end

  defp moderation_changes(:lock), do: [state: "locked"]
  defp moderation_changes(:unlock), do: [state: "open"]
  defp moderation_changes(:pin), do: [pinned: true]
  defp moderation_changes(:unpin), do: [pinned: false]

  defp topic_update_activity(actor, topic) do
    category_uri = Repo.one!(from c in Category, where: c.id == ^topic.category_id, select: c.uri)

    Repo.insert(
      Federation.activity_changeset(%{
        actor_uri: actor.uri,
        verb: "update",
        object_uri: topic.uri,
        target_uri: category_uri,
        payload:
          %{"type" => "Page", "state" => topic.state, "pinned" => topic.pinned}
          |> put_tags(topic)
      })
    )
  end

  defp put_tags(payload, %Topic{tags: tags}) when is_list(tags),
    do: Map.put(payload, "tag", tag_names(tags))

  defp put_tags(payload, _topic), do: payload

  ## Topics (TP-01)

  @doc """
  Returns a changeset for the new-topic form: the title, the first message's Markdown and the
  tags (`tag_ids`, TP-19), chosen among `available` (`Tags.available_tags/1` of the
  category): at least one when there are any.
  """
  def change_new_topic(attrs \\ %{}, available \\ []) do
    types = %{title: :string, body: :string, tag_ids: {:array, :string}}

    {%{}, types}
    |> Ecto.Changeset.cast(attrs, Map.keys(types))
    |> Ecto.Changeset.update_change(:title, &(&1 && String.trim(&1)))
    |> Ecto.Changeset.validate_required([:title, :body])
    |> Ecto.Changeset.validate_length(:title, max: 150)
    |> validate_tag_choice(available)
  end

  defp validate_tag_choice(changeset, available) do
    chosen = changeset |> Ecto.Changeset.get_field(:tag_ids) |> List.wrap() |> chosen_ids()
    known = MapSet.new(available, & &1.id)

    cond do
      Enum.any?(chosen, &(not MapSet.member?(known, &1))) ->
        Ecto.Changeset.add_error(changeset, :tag_ids, "are not tags of this category")

      chosen == [] and available != [] ->
        Ecto.Changeset.add_error(changeset, :tag_ids, "choose at least one tag")

      true ->
        Ecto.Changeset.put_change(changeset, :tag_ids, chosen)
    end
  end

  # Checkbox lists may carry an empty value (so that none checked is still sent).
  defp chosen_ids(ids), do: ids |> Enum.reject(&(&1 in ["", nil])) |> Enum.uniq()

  @doc """
  Starts a topic in `category`, as `user`, with a title and a first message (TP-01).

  The topic takes the chosen `tag_ids` (TP-19): at least one when the category offers tags.
  The user needs the `:start` right there (`{:error, :forbidden}` otherwise). The first
  message is posted closed together with the title (GM-14): it never was open. The topic and
  the message each get a URI (FD-01) and a `create` activity (FD-02), all in one transaction.

  `forked_from: message` starts it from a message of another topic (TP-09, "New topic from
  this"), any message the user may view, theirs or someone else's. The new topic links back
  to it, and the source topic's viewers get `{:forked, message_id}`.
  """
  @spec create_topic(User.t(), Category.t(), map(), keyword()) ::
          {:ok, Topic.t()} | {:error, :forbidden | :rate_limited | Ecto.Changeset.t()}
  def create_topic(%User{} = user, %Category{} = category, attrs, opts \\ []) do
    form = change_new_topic(attrs, Tags.available_tags(category))
    source = opts[:forked_from]

    result =
      cond do
        not can_start_topic?(user, category) -> {:error, :forbidden}
        source && !forkable?(user, source) -> {:error, :forbidden}
        not form.valid? -> {:error, Map.put(form, :action, :insert)}
        RateLimit.check(:new_topic, user.id) != :ok -> {:error, :rate_limited}
        true -> Repo.transact(fn -> insert_topic(user, category, form.changes, source) end)
      end

    # The source topic's viewers get its new "continued in" link (TP-04).
    with {:ok, _topic} when source != nil <- result,
         do: Messages.broadcast(source.topic_id, {:forked, source.id})

    result
  end

  # TP-09: a message the user may view, not deleted by a moderator (MO-02).
  defp forkable?(user, source) do
    case get_viewable_message(user, source.id) do
      %Message{deleted_at: nil} -> true
      _ -> false
    end
  end

  @doc """
  The categories where the user may start a topic (TP-01, TP-09), in order: they may view
  them and have the `:start` right; never the Archive.
  """
  @spec list_startable_categories(User.t() | nil) :: [Category.t()]
  def list_startable_categories(nil), do: []

  def list_startable_categories(%User{} = user) do
    from(c in Category, where: not c.archive, order_by: [asc: c.position, asc: c.name])
    |> Access.where_allowed(user, :start)
    |> Repo.all()
    |> Enum.filter(&Access.can?(user, :view, &1))
  end

  @doc """
  The topics started from each of the given messages (TP-09) that the user may view, as
  `%{message_id => [topic]}`, oldest first: the source's "continued in" links.
  """
  @spec list_forks(User.t() | nil, [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => [Topic.t()]}
  def list_forks(_user, []), do: %{}

  def list_forks(user, message_ids) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    from(t in Topic,
      where: t.forked_from_message_id in ^message_ids,
      where: t.category_id in subquery(viewable),
      order_by: [asc: t.created_at, asc: t.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.forked_from_message_id)
  end

  @doc """
  Returns true when the user may start a topic in the category: the `:start` right there,
  and never in the Archive, whose topics only come from deleted categories.
  """
  @spec can_start_topic?(User.t() | nil, Category.t()) :: boolean()
  def can_start_topic?(nil, _category), do: false
  def can_start_topic?(_user, %Category{archive: true}), do: false
  def can_start_topic?(%User{} = user, category), do: Access.can?(user, :start, category)

  defp insert_topic(user, category, %{title: title, body: body} = form, source) do
    tags = Enum.filter(Tags.available_tags(category), &(&1.id in Map.get(form, :tag_ids, [])))

    now = DateTime.utc_now()
    topic_id = Federation.generate_id()
    message_id = Federation.generate_id()

    topic =
      %Topic{
        id: topic_id,
        uri: Federation.uri(:topic, topic_id),
        category_id: category.id,
        author_id: user.id,
        slug: slugify(title, "topic"),
        forked_from_message_id: source && source.id,
        message_count: 1,
        last_activity_at: now
      }
      |> Topic.create_changeset(%{title: title})

    message =
      %Message{
        id: message_id,
        uri: Federation.uri(:message, message_id),
        topic_id: topic_id,
        author_id: user.id,
        opened_at: now,
        closes_at: now,
        closed_at: now
      }
      # The topic is not stored yet: its category says where the links are written.
      |> Message.closed_changeset(%{body_md: body}, author: user, category_id: category.id)

    with {:ok, topic} <- Repo.insert(topic),
         {_, _} <- Repo.insert_all("topic_tags", tag_rows(topic.id, tags)),
         {:ok, message} <- Repo.insert(message),
         {:ok, _} <- Idejo.Reading.auto_follow(user.id, topic.id),
         {:ok, _} <- Idejo.Notifications.notify_new(message, topic),
         {:ok, _} <-
           insert_activity(
             user,
             topic.uri,
             category.uri,
             topic_payload(title, source) |> Map.put("tag", tag_names(tags))
           ),
         {:ok, _} <- insert_activity(user, message.uri, topic.uri, %{"type" => "Note"}) do
      {:ok, topic}
    end
  end

  defp topic_payload(title, nil), do: %{"type" => "Page", "name" => title}

  defp topic_payload(title, source),
    do: %{"type" => "Page", "name" => title, "forkedFrom" => source.uri}

  defp tag_rows(topic_id, tags) do
    {:ok, topic_id} = Ecto.UUID.dump(topic_id)
    for tag <- tags, do: %{topic_id: topic_id, tag_id: Ecto.UUID.dump!(tag.id)}
  end

  defp tag_names(tags), do: Enum.map(tags, & &1.name)

  defp insert_activity(user, object_uri, target_uri, payload) do
    Repo.insert(
      Federation.activity_changeset(%{
        actor_uri: user.uri,
        verb: "create",
        object_uri: object_uri,
        target_uri: target_uri,
        payload: payload
      })
    )
  end

  @doc """
  Gets a topic by id, with its category, if the visitor (`nil`) or user may view that
  category; otherwise `nil`.
  """
  @spec get_viewable_topic(User.t() | nil, String.t()) :: Topic.t() | nil
  def get_viewable_topic(user, id) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Topic{} = topic <-
           Repo.get(Topic, id) |> Repo.preload([:category, tags: Tags.ordered()]),
         true <- Access.can?(user, :view, topic.category) do
      topic
    else
      _ -> nil
    end
  end

  @doc """
  Lists the topics a visitor without an account may view, most recently active first, at
  most `limit` (a sitemap holds 50,000 addresses). For the sitemap (SE-04); filtered in the
  query by `Idejo.Access.where_allowed/3`.
  """
  @spec list_public_topics(pos_integer()) :: [Topic.t()]
  def list_public_topics(limit \\ 50_000) do
    public = Category |> Access.where_allowed(nil, :view) |> select([c], c.id)

    Repo.all(
      from t in Topic,
        where: t.category_id in subquery(public),
        order_by: [desc: t.last_activity_at, desc: t.id],
        limit: ^limit
    )
  end

  @doc """
  Gets a message by id, with its topic, if the visitor (`nil`) or user may view the topic's
  category; otherwise `nil`. For message permalinks (TP-06).
  """
  @spec get_viewable_message(User.t() | nil, String.t()) :: Message.t() | nil
  def get_viewable_message(user, id) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Message{} = message <- Repo.get(Message, id) |> Repo.preload(topic: :category),
         true <- Access.can?(user, :view, message.topic.category) do
      message
    else
      _ -> nil
    end
  end

  @doc """
  Lists a category's topics for its page (TP-03), one page at a time: pinned topics first,
  then the most recently active, with their starters. The caller checks the category can be
  viewed.

  Returns `{topics, more?}`, where `more?` tells whether a next page exists.

  ## Options

    * `:page` - the page number, from 1. Defaults to 1.
    * `:per_page` - topics per page. Defaults to 30.
  """
  @spec list_topics(Category.t(), keyword()) :: {[Topic.t()], boolean()}
  def list_topics(%Category{id: category_id}, opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 30)
    page = max(Keyword.get(opts, :page, 1), 1)

    topics =
      Repo.all(
        from t in Topic,
          where: t.category_id == ^category_id,
          order_by: [desc: t.pinned, desc: t.last_activity_at, desc: t.id],
          offset: ^((page - 1) * per_page),
          limit: ^(per_page + 1),
          preload: [:author, tags: ^Tags.ordered()]
      )

    {Enum.take(topics, per_page), length(topics) > per_page}
  end

  @doc """
  Lists a topic's messages in the order they were opened (GM-08), with their authors.
  """
  @spec list_messages(Topic.t()) :: [Message.t()]
  def list_messages(%Topic{id: id}) do
    Repo.all(
      from m in Message,
        where: m.topic_id == ^id,
        order_by: [asc: m.opened_at, asc: m.id],
        preload: [:author, :versions, reply_to: :author]
    )
  end

  @doc """
  A topic's opening message, for a preview of the topic (TP-10 cards), or nil when a
  moderator deleted it (MO-02).
  """
  @spec opening_message(Topic.t()) :: Message.t() | nil
  def opening_message(%Topic{id: id}) do
    Repo.one(
      from m in Message,
        where: m.topic_id == ^id and is_nil(m.deleted_at),
        order_by: [asc: m.opened_at, asc: m.id],
        limit: 1
    )
  end

  ## Messages in a topic (TP-08)

  @doc """
  Returns a changeset for the message form: the Markdown body.
  """
  def change_new_message(attrs \\ %{}) do
    {%{}, %{body: :string}}
    |> Ecto.Changeset.cast(attrs, [:body])
    |> Ecto.Changeset.validate_required([:body])
  end

  @doc """
  Returns true when the user may post in the topic: the `:post` right in its category, and
  the topic open (locked and archived topics take no new messages).
  """
  @spec can_post?(User.t() | nil, Topic.t()) :: boolean()
  def can_post?(nil, _topic), do: false
  def can_post?(_user, %Topic{state: state}) when state != "open", do: false

  def can_post?(%User{} = user, %Topic{} = topic) do
    topic = Repo.preload(topic, :category)
    Access.can?(user, :post, topic.category)
  end

  @doc """
  Posts a message in a topic, as `user`, closed (until growing messages arrive in M3).

  With `"reply_to_id"` it is an inline reply (TP-08): it references one earlier message of
  the same topic and is shown with a short excerpt of it, in the topic's single flow (no side
  threads). The topic's message count and last activity move on, and the message gets a URI
  (FD-01) and a `create` activity (FD-02), in one transaction; then it is broadcast to the
  topic's viewers (TP-04).

  Refused with `{:error, :forbidden}` without the right or in a locked or archived topic.
  """
  @spec post_message(User.t(), Topic.t(), map()) ::
          {:ok, Message.t()} | {:error, :forbidden | :rate_limited | Ecto.Changeset.t()}
  def post_message(%User{} = user, %Topic{} = topic, attrs) do
    form = change_new_message(attrs)

    result =
      Repo.transact(fn ->
        # Locked, so a lock or a move cannot slip in between the check and the insert.
        topic = Repo.one!(from t in Topic, where: t.id == ^topic.id, lock: "FOR UPDATE")

        cond do
          not can_post?(user, topic) -> {:error, :forbidden}
          not form.valid? -> {:error, Map.put(form, :action, :insert)}
          RateLimit.check(:new_message, user.id) != :ok -> {:error, :rate_limited}
          true -> insert_message(user, topic, form, attrs["reply_to_id"])
        end
      end)

    # Stored first, then announced to the topic's viewers (TP-04, NF-02).
    with {:ok, message} <- result, do: Idejo.Messages.broadcast(topic.id, {:message, message})
    result
  end

  defp insert_message(user, topic, form, reply_to_id) do
    now = DateTime.utc_now()
    id = Federation.generate_id()

    with {:ok, reply_to} <- reply_target(topic, reply_to_id, form),
         {:ok, message} <-
           %Message{
             id: id,
             uri: Federation.uri(:message, id),
             topic_id: topic.id,
             author_id: user.id,
             reply_to_id: reply_to && reply_to.id,
             opened_at: now,
             closes_at: now,
             closed_at: now
           }
           |> Message.closed_changeset(%{body_md: form.changes.body},
             author: user,
             category_id: topic.category_id
           )
           |> Repo.insert(),
         {:ok, _} <-
           topic
           |> Ecto.Changeset.change(message_count: topic.message_count + 1, last_activity_at: now)
           |> Repo.update(),
         {:ok, _} <- Idejo.Reading.auto_follow(user.id, topic.id),
         {:ok, _} <- Idejo.Notifications.notify_new(message, topic),
         {:ok, _} <-
           insert_activity(user, message.uri, topic.uri, reply_payload(reply_to)) do
      {:ok, message}
    end
  end

  # A reply references a message of the same topic; anything else is refused.
  defp reply_target(_topic, blank, _form) when blank in [nil, ""], do: {:ok, nil}

  defp reply_target(topic, id, form) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Message{} = message <- Repo.get_by(Message, id: id, topic_id: topic.id) do
      {:ok, message}
    else
      _ ->
        {:error,
         form
         |> Ecto.Changeset.add_error(:body, "replies to a message that is not in this topic")
         |> Map.put(:action, :insert)}
    end
  end

  defp reply_payload(nil), do: %{"type" => "Note"}
  defp reply_payload(reply_to), do: %{"type" => "Note", "inReplyTo" => reply_to.uri}

  @doc """
  Gets one message of a topic, with its author, or `nil`: the message a reply is written to.
  """
  @spec get_topic_message(Topic.t(), String.t() | nil) :: Message.t() | nil
  def get_topic_message(%Topic{id: topic_id}, id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(Message, id: id, topic_id: topic_id) |> Repo.preload(:author)
      :error -> nil
    end
  end

  def get_topic_message(_topic, _id), do: nil

  @doc """
  A short plain-text excerpt of a message, for inline replies (TP-08): its text without
  formatting, cut at about `length` characters on a word.
  """
  @spec excerpt(Message.t(), pos_integer()) :: String.t()
  def excerpt(%Message{body_html: html}, length \\ 140) do
    text =
      html
      # TP-17: an emoji image reads as its emoji (its alt text).
      |> String.replace(~r{<img [^>]*\balt="([^"]*)"[^>]*>}, "\\1")
      # Blocks and line breaks part words; inline tags such as <strong> do not.
      |> String.replace(
        ~r{</?(p|li|ul|ol|h[1-6]|blockquote|pre|br|hr|tr|td|th|table)\b[^>]*>},
        " "
      )
      |> String.replace(~r/<[^>]*>/, "")
      |> unescape_html()
      |> String.split()
      |> Enum.join(" ")

    if String.length(text) <= length do
      text
    else
      cut = String.slice(text, 0, length)
      cut = String.replace(cut, ~r/\s+\S*$/u, "")
      cut <> "…"
    end
  end

  # The sanitiser escapes text with these entities only.
  defp unescape_html(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
    |> String.replace("&amp;", "&")
  end

  # One audit entry (SP-06) and one activity (FD-02) per change.
  defp record(admin, verb, before, after_, extra \\ %{}) do
    object = after_ || before
    before_snapshot = if before, do: Map.merge(snapshot(before), extra), else: nil

    with {:ok, _} <-
           Audit.record(admin, "category." <> verb, before_snapshot, snapshot(after_)),
         {:ok, _} <-
           Repo.insert(
             Federation.activity_changeset(%{
               actor_uri: admin.uri,
               verb: verb,
               object_uri: object.uri,
               payload: %{"type" => "Group", "name" => object.name, "slug" => object.slug}
             })
           ) do
      :ok
    end
  end

  defp snapshot(nil), do: nil
  defp snapshot(category), do: Audit.snapshot(category, [:name, :slug, :description, :position])

  # A blank slug field means "make one from the name".
  defp put_default_slug(attrs) do
    case attrs["slug"] do
      slug when is_binary(slug) and slug != "" ->
        if String.trim(slug) == "", do: default_slug(attrs), else: attrs

      _ ->
        default_slug(attrs)
    end
  end

  defp default_slug(attrs),
    do: Map.put(attrs, "slug", free_slug(slugify(attrs["name"] || "")))

  @doc """
  Turns a name into a slug: lowercase ASCII letters and digits separated by single dashes.
  Accents are dropped ("Café" → `cafe`); a name with no letters or digits gives `fallback`.
  """
  @spec slugify(String.t(), String.t()) :: String.t()
  def slugify(name, fallback \\ "category") do
    slug =
      name
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 50)
      |> String.trim("-")

    if slug == "", do: fallback, else: slug
  end

  defp free_slug(base) do
    taken =
      MapSet.new(Repo.all(from c in Category, where: like(c.slug, ^"#{base}%"), select: c.slug))

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  # Positions are rewritten as a whole; one change at a time.
  defp lock_categories, do: Repo.query!("LOCK TABLE categories IN SHARE ROW EXCLUSIVE MODE")
end

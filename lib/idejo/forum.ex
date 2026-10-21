# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum do
  @moduledoc """
  The forum structure: categories (RP-03) and topics (TP-01).

  Administrators create, rename, reorder and delete categories in **Admin → Categories**. Each
  change is audited (SP-06) and recorded as an activity (FD-02) in the same transaction.
  """

  import Ecto.Query, warn: false

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Federation
  alias Idejo.Forum.{Category, Topic}
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
        payload: %{"type" => "Page", "state" => topic.state, "pinned" => topic.pinned}
      })
    )
  end

  ## Topics (TP-01)

  @doc """
  Returns a changeset for the new-topic form: the title and the first message's Markdown.
  """
  def change_new_topic(attrs \\ %{}) do
    types = %{title: :string, body: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(attrs, Map.keys(types))
    |> Ecto.Changeset.update_change(:title, &(&1 && String.trim(&1)))
    |> Ecto.Changeset.validate_required([:title, :body])
    |> Ecto.Changeset.validate_length(:title, max: 150)
  end

  @doc """
  Starts a topic in `category`, as `user`, with a title and a first message (TP-01).

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
    form = change_new_topic(attrs)
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

  defp insert_topic(user, category, %{title: title, body: body}, source) do
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
      |> Message.closed_changeset(%{body_md: body})

    with {:ok, topic} <- Repo.insert(topic),
         {:ok, message} <- Repo.insert(message),
         {:ok, _} <- Idejo.Reading.auto_follow(user.id, topic.id),
         {:ok, _} <- Idejo.Notifications.notify_new(message, topic),
         {:ok, _} <-
           insert_activity(user, topic.uri, category.uri, topic_payload(title, source)),
         {:ok, _} <- insert_activity(user, message.uri, topic.uri, %{"type" => "Note"}) do
      {:ok, topic}
    end
  end

  defp topic_payload(title, nil), do: %{"type" => "Page", "name" => title}

  defp topic_payload(title, source),
    do: %{"type" => "Page", "name" => title, "forkedFrom" => source.uri}

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
         %Topic{} = topic <- Repo.get(Topic, id) |> Repo.preload(:category),
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
          preload: [:author]
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
           |> Message.closed_changeset(%{body_md: form.changes.body})
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

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.Tags do
  @moduledoc """
  Topic tags (TP-19; steward decision, 2026-10-22).

  Administrators make tags in **Admin → Tags**, server-wide or for one or more categories
  (`tag_categories`; steward decision, 2026-11-14), and rename them, change their categories
  or delete them; each change is audited (`tag.create`, `tag.update`, `tag.delete`). A
  topic's category offers the server-wide tags and its own (`available_tags/1`,
  `where_offered/2`): starting a topic there takes at least one of them when there are any.
  Users with the `:tag` right change a topic's tags (`Idejo.Forum.set_topic_tags/4`).

  "Filter by tag" (`/tags`) lists the topics carrying every chosen tag
  (`list_tagged_topics/3`), only in categories the user may view.
  """
  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Forum.{Category, Tag, Topic}
  alias Idejo.Repo

  @doc "The order tags are shown in, by name ignoring case; also for preloads."
  @spec ordered() :: Ecto.Query.t()
  def ordered, do: from(t in Tag, order_by: [asc: fragment("lower(?)", t.name), asc: t.id])

  @doc """
  Limits a query of tags to those offered in a category: the server-wide ones (no
  categories) and those linked to `category`, a category id or a query selecting ids (every
  category a user may view, `Access.where_allowed/3`).
  """
  @spec where_offered(Ecto.Queryable.t(), Ecto.UUID.t() | Ecto.Query.t()) :: Ecto.Query.t()
  def where_offered(query, %Ecto.Query{} = category_ids) do
    offered =
      from tc in "tag_categories",
        where: tc.category_id in subquery(category_ids),
        select: type(tc.tag_id, :binary_id)

    from t in query, where: t.id not in subquery(linked()) or t.id in subquery(offered)
  end

  def where_offered(query, category_id) when is_binary(category_id) do
    from t in query,
      where: t.id not in subquery(linked()) or t.id in subquery(linked_to(category_id))
  end

  # Tags with at least one category, and those of `category_id`.
  defp linked, do: from(tc in "tag_categories", select: type(tc.tag_id, :binary_id))

  defp linked_to(category_id),
    do:
      from(tc in "tag_categories",
        where: tc.category_id == type(^category_id, :binary_id),
        select: type(tc.tag_id, :binary_id)
      )

  @doc """
  Every tag, with its categories: the server-wide ones first, then by their first category in
  order, each by name. For the admin page.
  """
  @spec list_tags() :: [Tag.t()]
  def list_tags do
    from(t in Tag, preload: [categories: ^from(c in Category, order_by: c.position)])
    |> Repo.all()
    |> Enum.sort_by(fn tag ->
      case tag.categories do
        [] -> {0, 0, String.downcase(tag.name)}
        [first | _] -> {1, first.position, String.downcase(tag.name)}
      end
    end)
  end

  @doc "The tags a topic in the category may take: the server-wide ones and its own."
  @spec available_tags(Category.t()) :: [Tag.t()]
  def available_tags(%Category{id: category_id}),
    do: Repo.all(where_offered(ordered(), category_id))

  @doc """
  The tags the visitor (`nil`) or user may filter by: the server-wide ones and those of the
  categories they may view, by name, each with those of its categories they may view (in
  order; none for a server-wide tag).
  """
  @spec list_viewable_tags(User.t() | nil) :: [Tag.t()]
  def list_viewable_tags(user) do
    viewable = Category |> Access.where_allowed(user, :view)

    Repo.all(
      from t in where_offered(ordered(), select(viewable, [c], c.id)),
        preload: [categories: ^order_by(viewable, [c], c.position)]
    )
  end

  @doc """
  The topics carrying every one of `tags` (`match: :all`, the default) or at least one of
  them (`match: :any`; steward decision, 2026-10-24), in categories the visitor (`nil`) or
  user may view, the most recently active first, with their category, starter and tags, 30 a
  page: `{topics, more?}`. No tags, no topics.
  """
  @spec list_tagged_topics(User.t() | nil, [Tag.t()], keyword()) :: {[Topic.t()], boolean()}
  def list_tagged_topics(user, tags, opts \\ [])
  def list_tagged_topics(_user, [], _opts), do: {[], false}

  def list_tagged_topics(user, tags, opts) do
    per_page = Keyword.get(opts, :per_page, 30)
    page = max(Keyword.get(opts, :page, 1), 1)
    tag_ids = tags |> Enum.map(& &1.id) |> Enum.uniq()
    needed = if Keyword.get(opts, :match, :all) == :any, do: 1, else: length(tag_ids)

    carrying =
      from tt in "topic_tags",
        where: tt.tag_id in type(^tag_ids, {:array, :binary_id}),
        group_by: tt.topic_id,
        having: count(tt.tag_id) >= ^needed,
        select: type(tt.topic_id, :binary_id)

    topics =
      from(t in Topic,
        as: :topic,
        where: t.id in subquery(carrying),
        order_by: [desc: t.last_activity_at, desc: t.id],
        offset: ^((page - 1) * per_page),
        limit: ^(per_page + 1),
        preload: [:author, :category, tags: ^ordered()]
      )
      |> Access.where_topic_allowed(user, :view)
      |> Repo.all()

    {Enum.take(topics, per_page), length(topics) > per_page}
  end

  @doc "Returns a changeset for the new-tag form, or for renaming `tag`."
  def change_tag(tag \\ %Tag{}, attrs \\ %{})
  def change_tag(%Tag{id: nil} = tag, attrs), do: Tag.create_changeset(tag, attrs)
  def change_tag(%Tag{} = tag, attrs), do: Tag.update_changeset(tag, attrs)

  @doc """
  Creates a tag, as `admin`: `name`, and `category_ids` for a tag of those categories (none
  for a server-wide one; never the Archive; `category_id` names one). The slug is made from
  the name. Audited as `tag.create`.
  """
  @spec create_tag(User.t(), map()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def create_tag(%User{} = admin, attrs),
    do: Idejo.Access.as_administrator(admin, fn -> as_admin_insert_tag(admin, attrs) end)

  defp as_admin_insert_tag(%User{} = admin, attrs) do
    attrs = string_keys(attrs)
    slug = free_slug(Forum.slugify(attrs["name"] || "", "tag"))

    changeset =
      %Tag{slug: slug, categories: []}
      |> Tag.create_changeset(attrs)
      |> put_categories(category_ids(attrs) || [])

    Repo.transact(fn ->
      with {:ok, tag} <- Repo.insert(changeset),
           {:ok, _} <- Audit.record(admin, "tag.create", nil, snapshot(tag)) do
        {:ok, tag}
      end
    end)
  end

  defp string_keys(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  # The categories asked for: `category_ids` (a list; a form sends "" for none ticked) or
  # one `category_id`; nil when neither is given.
  defp category_ids(%{"category_ids" => ids}), do: ids |> List.wrap() |> Enum.reject(&(&1 == ""))
  defp category_ids(%{"category_id" => id}) when id in [nil, ""], do: []
  defp category_ids(%{"category_id" => id}), do: [id]
  defp category_ids(_attrs), do: nil

  defp put_categories(changeset, ids) do
    ids = Enum.uniq(ids)
    uuids = for id <- ids, {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid

    categories =
      Repo.all(from c in Category, where: c.id in ^uuids and not c.archive, order_by: c.position)

    if length(categories) == length(ids) do
      Ecto.Changeset.put_assoc(changeset, :categories, categories)
    else
      Ecto.Changeset.add_error(changeset, :category_ids, "is not a category")
    end
  end

  @doc """
  Renames a tag or changes its categories (`category_ids`), as `admin`; its slug stays.
  Topics in a category that no longer offers it lose it. Audited as `tag.update`.
  """
  @spec update_tag(User.t(), Tag.t(), map()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def update_tag(%User{} = admin, %Tag{} = tag, attrs),
    do: Idejo.Access.as_administrator(admin, fn -> as_admin_save_tag(admin, tag, attrs) end)

  defp as_admin_save_tag(%User{} = admin, %Tag{} = tag, attrs) do
    attrs = string_keys(attrs)
    tag = Repo.preload(tag, :categories)
    changeset = Tag.update_changeset(tag, attrs)

    changeset =
      case category_ids(attrs) do
        nil -> changeset
        ids -> put_categories(changeset, ids)
      end

    case changeset do
      %Ecto.Changeset{changes: changes, valid?: true} when changes == %{} ->
        {:ok, tag}

      changeset ->
        Repo.transact(fn -> save_tag(admin, tag, changeset) end)
    end
  end

  defp save_tag(admin, tag, changeset) do
    with {:ok, updated} <- Repo.update(changeset),
         _ = drop_unoffered(updated),
         {:ok, _} <- Audit.record(admin, "tag.update", snapshot(tag), snapshot(updated)) do
      {:ok, updated}
    end
  end

  # Topics whose category no longer offers `tag` lose it; a server-wide tag stays everywhere.
  defp drop_unoffered(%Tag{categories: []}), do: 0

  defp drop_unoffered(%Tag{id: id, categories: categories}) do
    category_ids = Enum.map(categories, & &1.id)

    elsewhere =
      from t in Topic,
        where: not is_nil(t.category_id) and t.category_id not in ^category_ids,
        select: t.id

    {count, _} =
      Repo.delete_all(
        from tt in "topic_tags",
          where: tt.tag_id == type(^id, :binary_id),
          where: tt.topic_id in subquery(elsewhere)
      )

    count
  end

  @doc """
  Deletes a tag, as `admin`; topics lose it, even when it was their only one. Audited as
  `tag.delete`, with how many topics carried it.
  """
  @spec delete_tag(User.t(), Tag.t()) :: {:ok, Tag.t()} | {:error, term()}
  def delete_tag(%User{} = admin, %Tag{} = tag),
    do: Idejo.Access.as_administrator(admin, fn -> as_admin_remove_tag(admin, tag) end)

  defp as_admin_remove_tag(%User{} = admin, %Tag{} = tag) do
    tag = Repo.preload(tag, :categories)

    Repo.transact(fn ->
      topics =
        Repo.aggregate(
          from(tt in "topic_tags", where: tt.tag_id == type(^tag.id, :binary_id)),
          :count
        )

      with {:ok, deleted} <- Repo.delete(tag),
           {:ok, _} <-
             Audit.record(admin, "tag.delete", Map.put(snapshot(tag), "topics", topics), nil) do
        {:ok, deleted}
      end
    end)
  end

  @doc "Counts the topics carrying each tag, as a map from tag id. For the admin page."
  @spec topic_counts() :: %{Ecto.UUID.t() => non_neg_integer()}
  def topic_counts do
    Repo.all(
      from tt in "topic_tags",
        group_by: tt.tag_id,
        select: {type(tt.tag_id, :binary_id), count()}
    )
    |> Map.new()
  end

  @doc """
  Removes from the topics the tags `category_id` does not offer: a topic moved to another
  category keeps only the server-wide tags and the new category's (TP-15).
  """
  @spec drop_foreign_tags([Ecto.UUID.t()], Ecto.UUID.t()) :: non_neg_integer()
  def drop_foreign_tags(topic_ids, category_id) do
    foreign =
      from t in Tag,
        where: t.id in subquery(linked()) and t.id not in subquery(linked_to(category_id)),
        select: t.id

    {count, _} =
      Repo.delete_all(
        from tt in "topic_tags",
          where: tt.topic_id in type(^topic_ids, {:array, :binary_id}),
          where: tt.tag_id in subquery(foreign)
      )

    count
  end

  @doc """
  Deletes the tags only `category_id` holds, as its deletion would leave them server-wide;
  tags it shares with other categories stay theirs. Called by `Forum.delete_category/3`.
  """
  @spec delete_own_tags(Ecto.UUID.t()) :: non_neg_integer()
  def delete_own_tags(category_id) do
    shared =
      from tc in "tag_categories",
        where: tc.category_id != type(^category_id, :binary_id),
        select: type(tc.tag_id, :binary_id)

    {count, _} =
      Repo.delete_all(
        from t in Tag,
          where: t.id in subquery(linked_to(category_id)) and t.id not in subquery(shared)
      )

    count
  end

  defp snapshot(tag) do
    tag
    |> Audit.snapshot([:name, :slug])
    |> Map.put("category_ids", Enum.map(tag.categories, & &1.id))
  end

  defp free_slug(base) do
    taken = MapSet.new(Repo.all(from t in Tag, where: like(t.slug, ^"#{base}%"), select: t.slug))

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end
end

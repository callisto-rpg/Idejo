# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.Tags do
  @moduledoc """
  Topic tags (TP-19; steward decision, 2026-10-22).

  Administrators make tags in **Admin → Tags**, server-wide or for one category, and rename
  or delete them; each change is audited (`tag.create`, `tag.update`, `tag.delete`). A
  topic's category offers the server-wide tags and its own (`available_tags/1`): starting a
  topic there takes at least one of them when there are any. Users with the `:tag` right
  change a topic's tags (`Idejo.Forum.set_topic_tags/4`).

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
  Every tag, with its category: the server-wide ones first, then by category in order, each
  by name. For the admin page.
  """
  @spec list_tags() :: [Tag.t()]
  def list_tags do
    Repo.all(
      from t in Tag,
        left_join: c in assoc(t, :category),
        order_by: [
          asc: fragment("? IS NOT NULL", t.category_id),
          asc: c.position,
          asc: fragment("lower(?)", t.name)
        ],
        preload: [category: c]
    )
  end

  @doc "The tags a topic in the category may take: the server-wide ones and its own."
  @spec available_tags(Category.t()) :: [Tag.t()]
  def available_tags(%Category{id: category_id}) do
    Repo.all(from t in ordered(), where: is_nil(t.category_id) or t.category_id == ^category_id)
  end

  @doc """
  The tags the visitor (`nil`) or user may filter by: the server-wide ones and those of the
  categories they may view, with their category, by name.
  """
  @spec list_viewable_tags(User.t() | nil) :: [Tag.t()]
  def list_viewable_tags(user) do
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)

    Repo.all(
      from t in ordered(),
        where: is_nil(t.category_id) or t.category_id in subquery(viewable),
        preload: :category
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
    viewable = Category |> Access.where_allowed(user, :view) |> select([c], c.id)
    needed = if Keyword.get(opts, :match, :all) == :any, do: 1, else: length(tag_ids)

    carrying =
      from tt in "topic_tags",
        where: tt.tag_id in type(^tag_ids, {:array, :binary_id}),
        group_by: tt.topic_id,
        having: count(tt.tag_id) >= ^needed,
        select: type(tt.topic_id, :binary_id)

    topics =
      Repo.all(
        from t in Topic,
          where: t.id in subquery(carrying),
          where: t.category_id in subquery(viewable),
          order_by: [desc: t.last_activity_at, desc: t.id],
          offset: ^((page - 1) * per_page),
          limit: ^(per_page + 1),
          preload: [:author, :category, tags: ^ordered()]
      )

    {Enum.take(topics, per_page), length(topics) > per_page}
  end

  @doc "Returns a changeset for the new-tag form, or for renaming `tag`."
  def change_tag(tag \\ %Tag{}, attrs \\ %{})
  def change_tag(%Tag{id: nil} = tag, attrs), do: Tag.create_changeset(tag, attrs)
  def change_tag(%Tag{} = tag, attrs), do: Tag.update_changeset(tag, attrs)

  @doc """
  Creates a tag, as `admin`: `name`, and `category_id` for a tag of one category (empty for a
  server-wide one; never the Archive). The slug is made from the name. Audited as
  `tag.create`.
  """
  @spec create_tag(User.t(), map()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def create_tag(%User{} = admin, attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    attrs = Map.update(attrs, "category_id", nil, &if(&1 == "", do: nil, else: &1))
    slug = free_slug(Forum.slugify(attrs["name"] || "", "tag"))

    changeset =
      %Tag{slug: slug}
      |> Tag.create_changeset(attrs)
      |> validate_category()

    Repo.transact(fn ->
      with {:ok, tag} <- Repo.insert(changeset),
           {:ok, _} <- Audit.record(admin, "tag.create", nil, snapshot(tag)) do
        {:ok, Repo.preload(tag, :category)}
      end
    end)
  end

  defp validate_category(changeset) do
    case Ecto.Changeset.get_change(changeset, :category_id) do
      nil ->
        changeset

      id ->
        with {:ok, id} <- Ecto.UUID.cast(id),
             %Category{archive: false} <- Repo.get(Category, id) do
          changeset
        else
          _ -> Ecto.Changeset.add_error(changeset, :category_id, "is not a category")
        end
    end
  end

  @doc "Renames a tag, as `admin`; its slug and category stay. Audited as `tag.update`."
  @spec update_tag(User.t(), Tag.t(), map()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def update_tag(%User{} = admin, %Tag{} = tag, attrs) do
    case Tag.update_changeset(tag, attrs) do
      %Ecto.Changeset{changes: changes} when changes == %{} ->
        {:ok, tag}

      changeset ->
        Repo.transact(fn -> save_tag(admin, tag, changeset) end)
    end
  end

  defp save_tag(admin, tag, changeset) do
    with {:ok, updated} <- Repo.update(changeset),
         {:ok, _} <- Audit.record(admin, "tag.update", snapshot(tag), snapshot(updated)) do
      {:ok, updated}
    end
  end

  @doc """
  Deletes a tag, as `admin`; topics lose it, even when it was their only one. Audited as
  `tag.delete`, with how many topics carried it.
  """
  @spec delete_tag(User.t(), Tag.t()) :: {:ok, Tag.t()} | {:error, term()}
  def delete_tag(%User{} = admin, %Tag{} = tag) do
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
  Removes from the topics the tags of categories other than `category_id`: a topic moved to
  another category keeps only the server-wide tags and the new category's (TP-15).
  """
  @spec drop_foreign_tags([Ecto.UUID.t()], Ecto.UUID.t()) :: non_neg_integer()
  def drop_foreign_tags(topic_ids, category_id) do
    foreign =
      from t in Tag,
        where: not is_nil(t.category_id) and t.category_id != ^category_id,
        select: t.id

    {count, _} =
      Repo.delete_all(
        from tt in "topic_tags",
          where: tt.topic_id in type(^topic_ids, {:array, :binary_id}),
          where: tt.tag_id in subquery(foreign)
      )

    count
  end

  defp snapshot(tag), do: Audit.snapshot(tag, [:name, :slug, :category_id])

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

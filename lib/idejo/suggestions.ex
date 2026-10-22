# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Suggestions do
  @moduledoc """
  What to suggest while a user types an inline link (TP-10; steward decision, 2026-10-22):
  after `@`, `+`, `#`, `/` or `$`, the items of that kind they recently dealt with first, then
  everything else matching what follows the sign ("@rob" → robert, Robin), at most 8.

    * `@` users: those who last wrote in this topic, then in the topics the user last read.
    * `+` roles: those the user may notify (`Idejo.Access.mentionable_roles/1`), by rank.
    * `#` topics, `/` categories, `$` tags: those of the topics the user last read, then
      the most recently active. Only what the user may view, filtered in the query.

  A user's own name is never suggested; visitors get nothing.
  """
  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Access.Role
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Tag, Topic}
  alias Idejo.Messages.Message
  alias Idejo.Reading.ReadPosition
  alias Idejo.Repo

  @limit 8
  @recent_topics 30

  @kinds %{"@" => :user, "+" => :role, "#" => :topic, "/" => :category, "$" => :tag}

  @doc "The kind of item a sign starts (`\"@\"` → `:user`), or nil."
  @spec kind(String.t()) :: :user | :role | :topic | :category | :tag | nil
  def kind(sign), do: Map.get(@kinds, sign)

  @doc """
  Suggests items of `kind` for `user` matching `query` (letters, digits, `_` and `-`; the
  rest is ignored). `topic_id:` ranks the people of that topic first.
  """
  @spec suggest(User.t() | nil, atom(), String.t(), keyword()) ::
          [User.t() | Role.t() | Topic.t() | Category.t() | Tag.t()]
  def suggest(user, kind, query, opts \\ [])
  def suggest(nil, _kind, _query, _opts), do: []

  def suggest(%User{} = user, kind, query, opts) do
    query =
      query |> String.downcase() |> String.replace(~r/[^a-z0-9_-]/, "") |> String.slice(0, 40)

    kind |> items(user, query, opts) |> Enum.take(@limit)
  end

  defp items(:user, user, query, opts) do
    recent = recent_authors(user, opts[:topic_id])

    matches =
      if query == "" do
        Repo.all(from u in User, where: u.id in ^recent and u.status == "active")
      else
        Repo.all(
          from u in User,
            where: u.status == "active" and u.id != ^user.id,
            where:
              like(fragment("lower(?)", u.username), ^"#{query}%") or
                like(fragment("lower(?)", u.display_name), ^"#{query}%") or
                like(fragment("lower(?)", u.display_name), ^"% #{query}%"),
            order_by: [asc: fragment("lower(?)", u.username)],
            limit: 50
        )
      end

    ranked(matches, recent)
  end

  defp items(:role, user, query, _opts) do
    user
    |> Access.mentionable_roles()
    |> Enum.filter(
      &(query == "" or starts?(Access.role_slug(&1), query) or starts?(&1.name, query))
    )
  end

  defp items(:topic, user, query, _opts) do
    recent = recent_topic_ids(user)

    base =
      from t in Topic,
        where: t.category_id in subquery(viewable(user)),
        order_by: [desc: t.last_activity_at, desc: t.id],
        limit: 50,
        preload: :category

    matches =
      if query == "" do
        Repo.all(from t in base, where: t.id in ^recent)
      else
        Repo.all(
          from t in base,
            where:
              like(t.slug, ^"%#{query}%") or like(fragment("lower(?)", t.title), ^"%#{query}%")
        )
      end

    ranked(matches, recent)
  end

  defp items(:category, user, query, _opts) do
    recent = user |> recent_topic_ids() |> categories_of()

    from(c in Category, order_by: [asc: c.position])
    |> Access.where_allowed(user, :view)
    |> Repo.all()
    |> Enum.filter(&(query == "" or starts?(&1.slug, query) or starts?(&1.name, query)))
    |> ranked(recent)
  end

  defp items(:tag, user, query, _opts) do
    recent_topics = recent_topic_ids(user)

    recent =
      Repo.all(
        from tt in "topic_tags",
          where: tt.topic_id in type(^recent_topics, {:array, :binary_id}),
          select: type(tt.tag_id, :binary_id)
      )
      |> Enum.uniq()

    from(t in Tag,
      where: is_nil(t.category_id) or t.category_id in subquery(viewable(user)),
      order_by: [asc: fragment("lower(?)", t.name)]
    )
    |> Repo.all()
    |> Enum.filter(&(query == "" or starts?(&1.slug, query) or starts?(&1.name, query)))
    |> ranked(recent)
  end

  defp items(_kind, _user, _query, _opts), do: []

  defp starts?(text, query), do: String.starts_with?(String.downcase(text), query)

  # The recent ones in their order first, then the rest as they came.
  defp ranked(items, recent_ids) do
    rank = recent_ids |> Enum.with_index() |> Map.new()
    Enum.sort_by(items, &Map.get(rank, &1.id, map_size(rank)))
  end

  defp viewable(user), do: Category |> Access.where_allowed(user, :view) |> select([c], c.id)

  # The topics the user last opened, most recent first.
  defp recent_topic_ids(%User{id: user_id} = user) do
    Repo.all(
      from rp in ReadPosition,
        join: t in Topic,
        on: t.id == rp.topic_id,
        where: rp.user_id == ^user_id and t.category_id in subquery(viewable(user)),
        order_by: [desc: rp.updated_at],
        limit: @recent_topics,
        select: rp.topic_id
    )
  end

  defp categories_of([]), do: []

  defp categories_of(topic_ids) do
    order = topic_ids |> Enum.with_index() |> Map.new()

    Repo.all(from t in Topic, where: t.id in ^topic_ids, select: {t.id, t.category_id})
    |> Enum.sort_by(fn {id, _} -> order[id] end)
    |> Enum.map(fn {_, category_id} -> category_id end)
    |> Enum.uniq()
  end

  # Who last wrote in this topic, then in the topics the user last opened; never the user.
  defp recent_authors(%User{} = user, topic_id) do
    Enum.uniq(authors_in(user, List.wrap(topic_id)) ++ authors_in(user, recent_topic_ids(user)))
  end

  defp authors_in(_user, []), do: []

  defp authors_in(%User{id: user_id}, topic_ids) do
    Repo.all(
      from m in Message,
        where: m.topic_id in ^topic_ids and m.author_id != ^user_id and is_nil(m.deleted_at),
        group_by: m.author_id,
        order_by: [desc: max(m.opened_at)],
        limit: 50,
        select: m.author_id
    )
  end
end

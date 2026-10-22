# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Body do
  @moduledoc """
  A message body's HTML (FD-03) with its inline links (TP-10; steward decision, 2026-10-22).
  Messages, previews and earlier versions all render through here.

    * `@username` naming an active user links to `/u/{id}`.
    * `+role` links to `/r/{slug}` and reads `+Role name`, when the author may notify that
      role (`Idejo.Access.mentionable_roles/1`).
    * `#slug` links to a topic the author may view (`/t/{id}`): the one with that slug they
      last wrote in, else the most recently active.
    * `/slug` links to a category the author may view (`/c/{slug}`).
    * `$slug` links to "Filter by tag" with a tag the author may view.

  A topic, category or tag link reads its name (`#Garden plans`) only when that name gives
  nothing away: everyone may view it, or it is in the message's own category. Otherwise it
  keeps the slug as typed. Unknown names stay plain text.

  The context says who writes and where: `author:` (a user) or `author_id:`, and
  `category_id:` or `topic_id:`. They are only loaded when the text has something to link.
  """
  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Access.UserRole
  alias Idejo.Accounts.User
  alias Idejo.Forum.{Category, Tag, Topic}
  alias Idejo.Markdown
  alias Idejo.Messages.Message
  alias Idejo.Repo

  @doc "Renders a message's Markdown to sanitised HTML, with its inline links."
  @spec to_html(String.t(), keyword()) :: String.t()
  def to_html(markdown, context \\ []) when is_binary(markdown) do
    case Markdown.references(markdown) do
      [] -> Markdown.to_html(markdown)
      references -> Markdown.to_html(markdown, links: links(references, context))
    end
  end

  @doc "The context of an existing message: its author, in its topic."
  @spec context(Message.t()) :: keyword()
  def context(%Message{author_id: author_id, topic_id: topic_id}),
    do: [author_id: author_id, topic_id: topic_id]

  @doc """
  The active users mentioned in the Markdown (TP-10), each once, outside code and links.
  For notifications (NO-01).
  """
  @spec mentioned_users(String.t()) :: [User.t()]
  def mentioned_users(markdown) when is_binary(markdown) do
    case Markdown.mentions(markdown) do
      [] -> []
      names -> users(names)
    end
  end

  @doc """
  The ids of the members of the roles the author notifies with `+role` in the Markdown, each
  once. For notifications (NO-01); the caller keeps those who may view the topic.
  """
  @spec mentioned_role_members(String.t(), keyword()) :: [Ecto.UUID.t()]
  def mentioned_role_members(markdown, context) when is_binary(markdown) do
    case slugs(Markdown.references(markdown), :role) do
      [] ->
        []

      slugs ->
        case context |> author() |> roles(slugs) |> Enum.map(& &1.id) do
          [] ->
            []

          role_ids ->
            Repo.all(
              from ur in UserRole,
                where: ur.role_id in ^role_ids,
                distinct: true,
                select: ur.user_id
            )
        end
    end
  end

  defp links(references, context) do
    author = if needs_author?(references), do: author(context)
    category_id = category_id(context)
    visible = visible_names(category_id)

    Map.new(
      Enum.map(
        users(slugs(references, :user)),
        &{{:user, String.downcase(&1.username)}, {"/u/" <> &1.id, nil}}
      ) ++
        Enum.map(
          roles(author, slugs(references, :role)),
          &{{:role, Access.role_slug(&1)}, {"/r/" <> Access.role_slug(&1), "+" <> role_label(&1)}}
        ) ++
        Enum.map(topics(author, slugs(references, :topic)), fn topic ->
          label = if visible.(topic.category_id), do: "#" <> topic.title
          {{:topic, topic.slug}, {"/t/" <> topic.id, label}}
        end) ++
        Enum.map(categories(author, slugs(references, :category)), fn category ->
          label = if visible.(category.id), do: "/" <> category.name
          {{:category, category.slug}, {"/c/" <> category.slug, label}}
        end) ++
        Enum.map(tags(author, slugs(references, :tag)), fn tag ->
          label = if tag.category_id == nil or visible.(tag.category_id), do: "$" <> tag.name
          {{:tag, tag.slug}, {"/tags?tags[]=" <> tag.slug, label}}
        end)
    )
  end

  # Built-in roles are stored lowercase ("moderator").
  defp role_label(%{built_in: true, name: name}), do: String.capitalize(name)
  defp role_label(%{name: name}), do: name

  defp slugs(references, kind), do: for({^kind, slug} <- references, do: slug)

  defp needs_author?(references), do: Enum.any?(references, fn {kind, _} -> kind != :user end)

  defp author(context) do
    case {context[:author], context[:author_id]} do
      {%User{} = user, _} -> user
      {_, id} when is_binary(id) -> Repo.get(User, id)
      _ -> nil
    end
  end

  defp category_id(context) do
    case {context[:category_id], context[:topic_id]} do
      {id, _} when is_binary(id) ->
        id

      {_, id} when is_binary(id) ->
        Repo.one(from t in Topic, where: t.id == ^id, select: t.category_id)

      _ ->
        nil
    end
  end

  # A name may show when everyone may view where it lives, or it is the message's category.
  defp visible_names(own_category_id) do
    fn
      ^own_category_id when own_category_id != nil -> true
      category_id -> Access.can?(nil, :view, %Category{id: category_id})
    end
  end

  defp users([]), do: []

  defp users(names) do
    Repo.all(
      from u in User, where: fragment("lower(?)", u.username) in ^names and u.status == "active"
    )
  end

  defp roles(_author, []), do: []
  defp roles(nil, _slugs), do: []

  defp roles(author, slugs) do
    author |> Access.mentionable_roles() |> Enum.filter(&(Access.role_slug(&1) in slugs))
  end

  defp topics(_author, []), do: []
  defp topics(nil, _slugs), do: []

  # Several topics may share a slug: the one the author last wrote in, else the most active.
  defp topics(%User{id: author_id} = author, slugs) do
    viewable = Category |> Access.where_allowed(author, :view) |> select([c], c.id)

    last_written =
      from m in Message,
        where: m.author_id == ^author_id,
        group_by: m.topic_id,
        select: %{topic_id: m.topic_id, at: max(m.opened_at)}

    from(t in Topic,
      left_join: w in subquery(last_written),
      on: w.topic_id == t.id,
      where: t.slug in ^slugs and t.category_id in subquery(viewable),
      order_by: [desc_nulls_last: w.at, desc: t.last_activity_at, desc: t.id]
    )
    |> Repo.all()
    |> Enum.uniq_by(& &1.slug)
  end

  defp categories(_author, []), do: []
  defp categories(nil, _slugs), do: []

  defp categories(author, slugs) do
    from(c in Category, where: c.slug in ^slugs)
    |> Access.where_allowed(author, :view)
    |> Repo.all()
  end

  defp tags(_author, []), do: []
  defp tags(nil, _slugs), do: []

  defp tags(author, slugs) do
    viewable = Category |> Access.where_allowed(author, :view) |> select([c], c.id)

    Repo.all(
      from t in Tag,
        where: t.slug in ^slugs,
        where: is_nil(t.category_id) or t.category_id in subquery(viewable)
    )
  end
end

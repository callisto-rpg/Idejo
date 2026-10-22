# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InlineCards do
  @moduledoc """
  The card an inline link opens in a topic (TP-10; steward decision, 2026-10-22): a preview of
  what it names, a link to open it, and an action where there is one. Built for the reader:
  what they may not view has no card (`load/4` returns nil), and the link is followed as
  without JavaScript.

    * `user` (`/u/{id}`): the user card, with "User actions" for server moderators.
    * `role` (`/r/{slug}`): its colour, member count and first members.
    * `topic` (`/t/{id}`): its category, starter, tags, message count and opening words;
      Follow / Unfollow for signed-in readers.
    * `category` (`/c/{slug}`): its description, topic count and latest topics; New topic
      for those who may start one.
    * `tag` (`/tags?tags[]={slug}`): where it belongs and the latest topics carrying it.
  """
  use IdejoWeb, :verified_routes

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Forum.Tags
  alias Idejo.Reading
  alias IdejoWeb.UserComponents

  @shown 3

  @doc """
  The card for `kind` and `ref` (an id or a slug, as in the link), for `viewer`, or nil.
  `return_to:` is where the user card's actions lead back to.
  """
  @spec load(String.t(), String.t(), Idejo.Accounts.User.t() | nil, keyword()) :: map() | nil
  def load(kind, ref, viewer, opts \\ [])

  def load("user", id, viewer, opts) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = user <- Idejo.Accounts.get_user(id) do
      %{
        kind: :user,
        path: ~p"/u/#{user.id}",
        card: UserComponents.card_data(user, viewer, return_to: opts[:return_to])
      }
    else
      _ -> nil
    end
  end

  def load("role", slug, _viewer, _opts) do
    with %{} = role <- Access.get_role_by_slug(slug) do
      {members, count} = Access.list_role_members(role, @shown)

      %{
        kind: :role,
        path: ~p"/r/#{Access.role_slug(role)}",
        role: role,
        members: members,
        count: count
      }
    end
  end

  def load("topic", id, viewer, _opts) do
    with %{} = topic <- Forum.get_viewable_topic(viewer, id) do
      topic = Idejo.Repo.preload(topic, :author)
      opening = Forum.opening_message(topic)

      %{
        kind: :topic,
        path: ~p"/t/#{topic.id}/#{topic.slug}",
        topic: topic,
        excerpt: opening && Forum.excerpt(opening, 200),
        following?: if(viewer, do: Reading.following?(viewer, topic))
      }
    end
  end

  def load("category", slug, viewer, _opts) do
    with %{} = category <- Forum.get_viewable_category(viewer, slug) do
      {topics, _more?} = Forum.list_topics(category, per_page: @shown)

      summary =
        viewer |> Forum.list_category_summaries() |> Enum.find(&(&1.category.id == category.id))

      %{
        kind: :category,
        path: ~p"/c/#{category.slug}",
        category: category,
        topics: topics,
        count: summary.topics,
        can_start?: Forum.can_start_topic?(viewer, category)
      }
    end
  end

  def load("tag", slug, viewer, _opts) do
    with %{} = tag <- viewer |> Tags.list_viewable_tags() |> Enum.find(&(&1.slug == slug)) do
      {topics, more?} = Tags.list_tagged_topics(viewer, [tag], per_page: @shown)

      %{
        kind: :tag,
        path: IdejoWeb.TopicComponents.tag_path([tag]),
        tag: tag,
        topics: topics,
        more?: more?
      }
    end
  end

  def load(_kind, _ref, _viewer, _opts), do: nil
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Api do
  @moduledoc """
  The resources of the official app's API (AP-11; steward decision, 2026-11-10), built from
  the same context data the web app shows, for one viewer, in a fixed number of queries
  whatever the list's length.

  Every function takes the viewer first and things they were allowed to load already
  (through the viewer-aware getters and lists of the other contexts), and returns maps with
  string keys, ready to encode as JSON: Markdown source and structured objects, never
  HTML. What a viewer may not see stays out: other members' emails, deleted text unless they
  moderate the category (MO-02), moderator-only versions (MO-06), voters, reporters.

  Addresses are absolute (`config :idejo, :base_uri`), so the app can use them as they are.
  """
  import Ecto.Query

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Api.Structure
  alias Idejo.Emoji
  alias Idejo.Forum
  alias Idejo.Forum.{Category, Forwards, Tag, Tags, Topic, TopicIcons}
  alias Idejo.Markdown
  alias Idejo.Messages
  alias Idejo.Messages.{Message, Polls}
  alias Idejo.Plugins
  alias Idejo.Reactions
  alias Idejo.Reading
  alias Idejo.Reading.Follow
  alias Idejo.Repo
  alias Idejo.Uploads
  alias Idejo.Uploads.Upload

  ## Addresses

  @doc "The server's own address, without a trailing slash."
  @spec base() :: String.t()
  def base, do: Application.fetch_env!(:idejo, :base_uri)

  @doc "An address made absolute: paths get the server's address; others stay."
  @spec absolute(String.t() | nil) :: String.t() | nil
  def absolute(nil), do: nil
  def absolute("/" <> _ = path), do: base() <> path
  def absolute(url) when is_binary(url), do: url

  @doc "When a time is ISO 8601 in UTC; nil stays nil."
  @spec time(DateTime.t() | NaiveDateTime.t() | nil) :: String.t() | nil
  def time(nil), do: nil
  def time(%DateTime{} = at), do: DateTime.to_iso8601(at)

  def time(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  ## People

  @doc """
  A user as an author or in a list: name, user tag, pictures, the role shown next to the name
  (`Access.shown_role/1`). Never an email. `roles` are theirs from `Access.roles_of_users/1`.
  """
  @spec person(User.t(), [Access.Role.t()] | nil) :: map()
  def person(%User{} = user, roles \\ nil) do
    role = roles && Access.shown_role(roles)

    %{
      "id" => user.id,
      "uri" => user.uri,
      "username" => user.username,
      "display_name" => user.display_name,
      "user_tag" => user.user_tag,
      "avatar_url" => absolute(Uploads.avatar_url(user)),
      "avatar_dark_url" => absolute(Uploads.dark_avatar_url(user)),
      "role" => role && %{"name" => role.name, "colour" => role.colour},
      "colour" => roles && Access.name_colour(roles),
      "deleted" => user.status == "deleted",
      "system" => user.status == "system"
    }
  end

  @doc """
  The user card (`/u/{id}`): the person, their bio's Markdown, their roles (guest left out),
  when they joined, and what the viewer may do: ignore them (`ignored_by_me`, nil when they
  may not, AC-06), write to them (`may_message`), ban them (server moderators).
  """
  @spec user_card(User.t() | nil, User.t()) :: map()
  def user_card(viewer, %User{} = user) do
    roles = Access.roles_of(user)
    shown = Enum.reject(roles, &(&1.built_in and &1.name == "guest"))

    user
    |> person(roles)
    |> Map.merge(%{
      "bio_md" => user.bio_md,
      "roles" => Enum.map(shown, &%{"id" => &1.id, "name" => &1.name, "colour" => &1.colour}),
      "joined_at" => time(user.created_at),
      "ignored_by_me" =>
        if(Accounts.may_ignore?(viewer, user), do: Accounts.ignoring?(viewer, user)),
      "may_message" => Idejo.Conversations.may_message?(viewer, user),
      "may_ban" => viewer != nil and Accounts.may_ban?(viewer, user),
      "banned" => if(viewer && Access.server_moderator?(viewer), do: Accounts.banned?(user))
    })
  end

  @doc "The signed-in user's own account: the card, their email (only here) and their choices."
  @spec me(User.t()) :: map()
  def me(%User{} = user) do
    user
    |> user_card(user)
    |> Map.merge(%{
      "email" => user.email,
      "verified" => Accounts.confirmed?(user),
      "welcomed" => user.welcomed_at != nil,
      "auto_punctuation" => user.auto_punctuation,
      "accepts_private_messages" => user.accepts_private_messages,
      "warning_pending" => user.warning_pending,
      "administrator" => Access.administrator?(user),
      "moderator" => Idejo.Moderation.moderator?(user),
      "server_moderator" => Access.server_moderator?(user)
    })
  end

  ## Categories

  @doc """
  The categories the viewer may view, in the home page's order (`Forum.list_category_summaries/1`),
  each with its group, counts, tags and the viewer's rights there.
  """
  @spec categories(User.t() | nil) :: [map()]
  def categories(viewer) do
    summaries = Forum.list_category_summaries(viewer)
    rights = rights(viewer, Enum.map(summaries, & &1.category.id))
    groups = Map.new(Forum.list_groups(), &{&1.id, &1})
    tags = category_tags(Enum.map(summaries, & &1.category.id))

    Enum.map(summaries, fn summary ->
      category(summary.category, summary, rights, groups, tags)
    end)
  end

  @doc "One category the viewer may view, as in `categories/1`."
  @spec category(User.t() | nil, Category.t()) :: map()
  def category(viewer, %Category{} = category) do
    summary =
      Enum.find(Forum.list_category_summaries(viewer), &(&1.category.id == category.id)) ||
        %{topics: 0, last_activity_at: nil}

    category(
      category,
      summary,
      rights(viewer, [category.id]),
      Map.new(Forum.list_groups(), &{&1.id, &1}),
      category_tags([category.id])
    )
  end

  defp category(category, summary, rights, groups, tags) do
    group = category.group_id && groups[category.group_id]

    %{
      "id" => category.id,
      "uri" => category.uri,
      "title" => category.name,
      "slug" => category.slug,
      "url" => base() <> "/c/" <> category.slug,
      "description" => category.description,
      "icon" => category.icon,
      "colour" => category.colour,
      "group" => group && %{"id" => group.id, "name" => group.name, "position" => group.position},
      "position" => category.position,
      "archive" => category.archive,
      "topic_type" => category.topic_type,
      "new_topics" => category.new_topics,
      "topics_count" => summary.topics,
      "last_activity_at" => time(summary.last_activity_at),
      "tags" => Enum.map(Map.get(tags, category.id, []), &tag/1),
      "permissions" => %{
        "view" => true,
        "create_topic" => category.id in rights.start and not category.archive,
        "post" => category.id in rights.post,
        "attach" => category.id in rights.post,
        "react" => category.id in rights.view and rights.verified?,
        "tag" => category.id in rights.tag,
        "moderate" => category.id in rights.moderate
      }
    }
  end

  # The viewer's rights in the categories, one query per right (never `can?/3` in a loop).
  defp rights(viewer, category_ids) do
    allowed = fn right ->
      Category
      |> Access.where_allowed(viewer, right)
      |> where([category: c], c.id in ^category_ids)
      |> select([category: c], c.id)
      |> Repo.all()
    end

    %{
      view: allowed.(:view),
      start: allowed.([:start, :view]),
      post: allowed.([:post, :view]),
      tag: allowed.([:tag, :view]),
      moderate: allowed.([:moderate, :view]),
      verified?: viewer != nil and Accounts.confirmed?(viewer)
    }
  end

  # The tags each category offers (`Tags.available_tags/1`): the server-wide ones and its own.
  defp category_tags(category_ids) do
    tags = Repo.all(from t in Tag, order_by: [asc: t.name])
    server_wide = Enum.filter(tags, &is_nil(&1.category_id))

    Map.new(category_ids, fn id ->
      {id, server_wide ++ Enum.filter(tags, &(&1.category_id == id))}
    end)
  end

  @doc "A tag: id, name and slug."
  @spec tag(Tag.t()) :: map()
  def tag(%Tag{} = tag), do: %{"id" => tag.id, "name" => tag.name, "slug" => tag.slug}

  ## Topics

  @doc """
  Topics the viewer may view (they come from a viewer-aware list), each with what the viewer
  sees of it: unread count, the sidebar's dot (`mention_state`), followed and muted.
  `expanded: true` adds the expanded topic list's preview (`Forum.topic_previews/1`).
  `unread:` gives counts already known (the Unread page's).
  """
  @spec topics(User.t() | nil, [Topic.t()], keyword()) :: [map()]
  def topics(viewer, topics, opts \\ []) do
    ids = Enum.map(topics, & &1.id)
    topics = Repo.preload(topics, [:author, :icon, tags: Tags.ordered()])
    unread = Keyword.get_lazy(opts, :unread, fn -> Reading.unread_counts(viewer, ids) end)
    levels = Reading.activity(viewer, ids)
    follows = follows(viewer, ids)
    previews = if opts[:expanded], do: Forum.topic_previews(ids), else: %{}
    inactive = topics |> Reading.put_inactive() |> Map.new(&{&1.id, &1.inactive})

    Enum.map(topics, fn topic ->
      topic
      |> topic_map(viewer, unread, levels, follows, inactive)
      |> put_preview(previews[topic.id], opts[:expanded])
    end)
  end

  @doc "One topic, as in `topics/2`, with its first message's id."
  @spec topic(User.t() | nil, Topic.t()) :: map()
  def topic(viewer, %Topic{} = topic) do
    [map] = topics(viewer, [topic])
    first = Forum.TopicWindow.first(topic)
    Map.put(map, "first_message_id", first && first.id)
  end

  defp topic_map(topic, viewer, unread, levels, follows, inactive) do
    follow = follows[topic.id]

    followed =
      case follow do
        %Follow{following: following} -> following
        nil -> viewer != nil and topic.autofollow
      end

    %{
      "id" => topic.id,
      "uri" => topic.uri,
      "title" => topic.title,
      "slug" => topic.slug,
      "url" => base() <> "/t/" <> topic.id <> "/" <> topic.slug,
      "category_id" => topic.category_id,
      "private" => topic.private,
      "tags" => Enum.map(topic.tags, &tag/1),
      "author" => if(topic.topical, do: nil, else: topic.author && person(topic.author)),
      "topical" => topic.topical,
      "icon" => topic.icon && absolute(TopicIcons.url(topic.icon)),
      "created_at" => time(topic.created_at),
      "last_activity_at" => time(topic.last_activity_at),
      "messages_count" => topic.message_count,
      "unread_count" => Map.get(unread, topic.id, 0),
      "mention_state" => mention_state(levels[topic.id]),
      "followed" => followed,
      "muted" => match?(%Follow{muted: true}, follow),
      "locked" => topic.state == "locked",
      "archived" => topic.state == "archived",
      "pinned" => topic.pinned,
      "inactive" => Map.get(inactive, topic.id, false),
      "followed_by_everyone" => topic.autofollow,
      "continues_from" =>
        topic.forked_from_message_id && %{"message_id" => topic.forked_from_message_id}
    }
  end

  defp mention_state(nil), do: "none"
  defp mention_state(:new), do: "new"
  defp mention_state(:role_mention), do: "role"
  defp mention_state(:reply), do: "reply"
  defp mention_state(:mention), do: "mention"

  defp follows(nil, _ids), do: %{}
  defp follows(_viewer, []), do: %{}

  defp follows(%User{id: user_id}, ids) do
    Repo.all(from f in Follow, where: f.user_id == ^user_id and f.topic_id in ^ids)
    |> Map.new(&{&1.topic_id, &1})
  end

  defp put_preview(map, _preview, expanded?) when expanded? in [nil, false], do: map
  defp put_preview(map, nil, true), do: Map.put(map, "preview", nil)

  defp put_preview(map, preview, true) do
    Map.put(map, "preview", %{
      "first_excerpt" => preview.first && Forum.excerpt(preview.first),
      "images" => Enum.map(preview.images, &absolute/1),
      "images_count" => length(preview.images),
      "latest" =>
        Enum.map(preview.latest, fn message ->
          %{
            "message_id" => message.id,
            "author_name" => Messages.author_name(message),
            "excerpt" => Forum.excerpt(message)
          }
        end),
      "writers" => Enum.map(Enum.take(preview.participants, 5), &person/1),
      "writers_count" => preview.participant_count
    })
  end

  ## Messages

  @doc """
  The messages of one topic or conversation, for the viewer who may read it, in order
  (AP-11): each with its author and role, Markdown, structured mentions, images, spoiler,
  replies, forward, poll, plugins and reactions, in a fixed number of queries. Deleted
  messages keep their place; their text only for moderators of the category (MO-02).
  """
  @spec messages(User.t() | nil, Topic.t(), [Message.t()]) :: [map()]
  def messages(_viewer, _topic, []), do: []

  def messages(viewer, %Topic{} = topic, messages) do
    messages = messages |> Repo.preload(Messages.shown()) |> Repo.preload(topic: :category)
    ids = Enum.map(messages, & &1.id)
    moderator? = moderator?(viewer, topic)

    context = %{
      viewer: viewer,
      moderator?: moderator?,
      roles: Access.roles_of_users(messages |> Enum.map(& &1.author) |> Enum.uniq_by(& &1.id)),
      ignored: Accounts.ignored_ids(viewer),
      reactions: Reactions.summaries(ids),
      polls: Polls.summaries(ids),
      forks: Forum.list_forks(viewer, ids),
      quotes: quotes(viewer, messages),
      forwards:
        Forwards.readable_ids(
          viewer,
          Enum.map(messages, & &1.forwarded_from_id) |> Enum.reject(&is_nil/1)
        ),
      uploads: uploads(messages),
      plugins: Plugins.active(),
      slugs: slugs(messages)
    }

    Enum.map(messages, &message_map(&1, context))
  end

  @doc "One message, as in `messages/3`."
  @spec message(User.t() | nil, Message.t()) :: map()
  def message(viewer, %Message{} = message) do
    message = Repo.preload(message, topic: :category)
    [map] = messages(viewer, message.topic, [message])
    map
  end

  @doc "Whether the viewer moderates the topic's category (never a private conversation's)."
  @spec moderator?(User.t() | nil, Topic.t()) :: boolean()
  def moderator?(nil, _topic), do: false
  def moderator?(_viewer, %Topic{private: true}), do: false

  def moderator?(viewer, %Topic{} = topic) do
    topic = Repo.preload(topic, :category)
    Access.can?(viewer, :moderate, topic)
  end

  defp message_map(message, context) do
    deleted? = message.deleted_at != nil
    forks = Map.get(context.forks, message.id, [])

    %{
      "id" => message.id,
      "uri" => message.uri,
      "topic_id" => message.topic_id,
      "url" => base() <> "/m/" <> message.id,
      "author" => author(message, context),
      "state" => if(deleted?, do: "deleted", else: message.state),
      "deleted_by" => deleted_by(message),
      "spoiler" => if(message.spoiler, do: %{"overlay" => message.spoiler_label}),
      "reactions" => reactions(context.reactions[message.id], context.viewer),
      "edited" => message.edited,
      "moderator_edited" => message.moderator_edited,
      "versions_count" => if(context.moderator?, do: versions_count(message)),
      "scheduled" => message.scheduled,
      "held" => message.held,
      "anonymous" => message.anonymous,
      "continues_topic_id" => forks |> List.first() |> then(&(&1 && &1.id)),
      "continued_in" => Enum.map(forks, &%{"topic_id" => &1.id, "title" => &1.title}),
      "cursor" => message.change_seq,
      "opened_at" => time(message.opened_at),
      "closed_at" => time(message.closed_at),
      "updated_at" => time(message.updated_at)
    }
    |> Map.merge(content(message, context, not deleted? or context.moderator?))
  end

  # What the message says: none of it for a deleted message, but to its moderators (MO-02).
  defp content(_message, _context, false = _shown?) do
    %{
      "body_md" => nil,
      "mentions" => [],
      "images" => [],
      "inline_spoilers" => false,
      "replies_to" => [],
      "forwarded_from" => nil,
      "poll" => nil,
      "plugins" => []
    }
  end

  defp content(message, context, true) do
    html = message.body_html || ""

    %{
      "body_md" => message.body_md,
      "mentions" => mentions(message.body_html, context.slugs),
      "images" => images(message.body_md, context.uploads),
      "inline_spoilers" => String.contains?(html, ~s(class="spoiler")),
      "replies_to" => replies_to(message, context),
      "forwarded_from" => forwarded_from(message, context),
      "poll" => poll(context.polls[message.id], message, context.viewer),
      "plugins" => plugins(message, context.plugins)
    }
  end

  defp author(%Message{anonymous: true} = message, _context),
    do: %{
      "id" => nil,
      "display_name" => Messages.author_name(message),
      "topical" => true,
      "ignored_by_me" => false
    }

  defp author(%Message{author: author}, context) do
    author
    |> person(context.roles[author.id])
    |> Map.put("ignored_by_me", MapSet.member?(context.ignored, author.id))
  end

  defp deleted_by(%Message{deleted_at: nil}), do: nil

  defp deleted_by(message),
    do: if(Messages.deleted_by_author?(message), do: "author", else: "moderator")

  defp versions_count(%Message{versions: versions}) when is_list(versions), do: length(versions)
  defp versions_count(_message), do: 0

  # What inline links lead to: users and topics by id, roles by slug, and categories and
  # tags by slug with their id read here (one query each, only when some message has them).
  defp slugs(messages) do
    links = Enum.flat_map(messages, &Structure.mentions(&1.body_html))
    wanted = fn type -> for(%{type: ^type, ref: ref} <- links, uniq: true, do: ref) end

    categories =
      case wanted.("category") do
        [] ->
          %{}

        slugs ->
          Repo.all(from c in Category, where: c.slug in ^slugs, select: {c.slug, {c.id, c.name}})
          |> Map.new()
      end

    tags =
      case wanted.("tag") do
        [] ->
          %{}

        slugs ->
          Repo.all(from t in Tag, where: t.slug in ^slugs, select: {t.slug, {t.id, t.name}})
          |> Map.new()
      end

    %{"category" => categories, "tag" => tags}
  end

  defp mentions(nil, _slugs), do: []

  defp mentions(html, slugs) do
    for %{type: type, ref: ref, text: text} <- Structure.mentions(html) do
      {id, name} =
        case type do
          type when type in ["category", "tag"] -> Map.get(slugs[type], ref, {nil, nil})
          "role" -> {ref, String.trim_leading(text, "+")}
          _other -> {ref, text |> String.trim_leading("@") |> String.trim_leading("#")}
        end

      %{
        "type" => type,
        "text" => text,
        "id" => id,
        "slug" => if(type in ["role", "category", "tag"], do: ref),
        "name" => name
      }
    end
  end

  defp uploads(messages) do
    names =
      messages
      |> Enum.flat_map(&Structure.images(&1.body_md))
      |> Enum.map(& &1.upload)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case names do
      [] ->
        %{}

      names ->
        Repo.all(
          from u in Upload, where: u.path in ^names, select: {u.path, {u.id, u.width, u.height}}
        )
        |> Map.new()
    end
  end

  defp images(nil, _uploads), do: []

  defp images(markdown, uploads) do
    for image <- Structure.images(markdown) do
      {id, width, height} = Map.get(uploads, image.upload, {nil, nil, nil})

      %{
        "upload_id" => id,
        "url" => absolute(image.url),
        "alt" => image.alt,
        "width" => width,
        "height" => height
      }
    end
  end

  # The message it replies to (TP-08) and the ones it quotes inline, those the viewer may read.
  defp quotes(viewer, messages) do
    ids =
      messages
      |> Enum.flat_map(fn message ->
        List.wrap(message.reply_to_id) ++ Markdown.quoted_messages(message.body_md || "")
      end)
      |> Enum.uniq()

    readable = Forwards.readable_ids(viewer, ids)

    case MapSet.to_list(readable) do
      [] ->
        %{}

      ids ->
        Repo.all(from m in Message, where: m.id in ^ids, preload: :author)
        |> Map.new(&{&1.id, &1})
    end
  end

  defp replies_to(message, context) do
    ids =
      Enum.uniq(List.wrap(message.reply_to_id) ++ Markdown.quoted_messages(message.body_md || ""))

    for id <- ids, quoted = context.quotes[id] do
      %{
        "message_id" => quoted.id,
        "author_name" => Messages.author_name(quoted),
        "excerpt" => if(quoted.deleted_at, do: nil, else: Forum.excerpt(quoted)),
        "inline" => id != message.reply_to_id
      }
    end
  end

  # The original: whole when the viewer may read it, or when the forwarder wrote it (then
  # without the topic's name); else only that a message was forwarded.
  defp forwarded_from(%Message{forwarded_from_id: nil}, _context), do: nil

  defp forwarded_from(%Message{forwarded_from: %Message{} = source} = message, context) do
    readable? = MapSet.member?(context.forwards, source.id)
    visible? = (readable? or source.author_id == message.author_id) and is_nil(source.deleted_at)
    named? = readable? and not source.topic.private

    %{"message_id" => source.id, "visible" => visible?}
    |> Map.merge(
      only(visible?, %{
        "author_name" => fn -> Messages.author_name(source) end,
        "body_md" => fn -> source.body_md end,
        "excerpt" => fn -> Forum.excerpt(source) end
      })
    )
    |> Map.merge(
      only(named?, %{
        "topic_id" => fn -> source.topic_id end,
        "topic_title" => fn -> source.topic.title end
      })
    )
  end

  defp forwarded_from(_message, _context), do: nil

  # Each value when `shown?`, else nil.
  defp only(shown?, fields),
    do: Map.new(fields, fn {key, value} -> {key, if(shown?, do: value.())} end)

  @doc """
  A poll as its viewer sees it: counts only when `Polls.results_shown?/4` allows (else nil),
  the viewer's own votes, never who voted.
  """
  @spec poll(map() | nil, Message.t(), User.t() | nil) :: map() | nil
  def poll(nil, _message, _viewer), do: nil

  def poll(summary, message, viewer) do
    shown? = Polls.results_shown?(summary, viewer, message)

    %{
      "id" => summary.id,
      "question" => summary.question,
      "multiple" => summary.multiple,
      "hidden_until_closed" => summary.hide_results,
      "closes_at" => time(summary.closes_at),
      "closed" => not Polls.open?(summary),
      "results_shown" => shown?,
      "total" => if(shown?, do: summary.voters),
      "my_votes" => if(viewer, do: Map.get(summary.votes, viewer.id, []), else: []),
      "options" =>
        Enum.map(summary.options, fn option ->
          %{
            "id" => option.id,
            "text" => option.text,
            "emoji" => option.emoji,
            "colour" => option.colour,
            "count" => if(shown?, do: option.count)
          }
        end)
    }
  end

  defp plugins(message, active) do
    for embed <- Plugins.shown(message.embeds, active) do
      # Markdown only (AP-11): a card's rendered HTML stays on the server.
      %{
        "command" => embed.plugin,
        "block" => embed.block,
        "params" => Map.drop(embed.data, ["body_html"])
      }
    end
  end

  @doc "A message's reactions (TP-17): each emoji once, its picture, count and whether it is the viewer's."
  @spec reactions([map()] | nil, User.t() | nil) :: [map()]
  def reactions(nil, _viewer), do: []

  def reactions(summary, viewer) do
    for %{emoji: name, count: count, user_ids: user_ids} <- summary do
      emoji = Emoji.lookup(name)

      %{
        "emoji" => ":" <> name <> ":",
        "name" => name,
        "char" => emoji && emoji.char,
        "image_url" => emoji && absolute(emoji.src),
        "count" => count,
        "mine" => viewer != nil and viewer.id in user_ids
      }
    end
  end
end

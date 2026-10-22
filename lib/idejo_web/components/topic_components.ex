# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicComponents do
  @moduledoc """
  How categories and topics are shown in lists: the category's mark (its initial on a tint
  of its own), a topic row (TP-03), tags (TP-19), and times as "5 min ago".
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext
  use IdejoWeb, :verified_routes

  import IdejoWeb.CoreComponents, only: [icon: 1]

  alias IdejoWeb.UserComponents

  @hues 8

  @doc """
  A category's mark: its initial on one of #{@hues} tints, picked from its id so it never
  changes. Decorative; the name is always next to it. Classes, not `style` (SP-05).
  """
  attr :category, :map, required: true
  attr :size, :atom, values: [:small, :large], default: :small

  def category_mark(assigns) do
    ~H"""
    <span
      class={["category-mark", "hue-#{hue(@category)}", @size == :large && "category-mark-lg"]}
      aria-hidden="true"
    >
      {@category.name |> String.first() |> String.upcase()}
    </span>
    """
  end

  @doc "The tint of a category's mark, 0 to #{@hues - 1}."
  @spec hue(map()) :: non_neg_integer()
  def hue(%{id: id}), do: :erlang.phash2(id, @hues)

  @doc """
  A topic in a list (TP-03): its starter's avatar, the title (a direct child of the `<li>`,
  which tests rely on), badges, then who started it, where and when it was last active, and
  the message count.

  * `category` - also show the topic's category (lists across categories; needs it loaded).
  * `lead` - `:category` puts the category's mark and name in place of the starter's avatar
    and name (the home page's active topics; needs the category loaded).
  * `unread` - the "N new" marker (TP-07), or nil.
  """
  attr :topic, :map, required: true
  attr :category, :boolean, default: false
  attr :lead, :atom, values: [:author, :category], default: :author
  attr :unread, :integer, default: nil

  def topic_row(assigns) do
    ~H"""
    <li id={"topic-#{@topic.id}"} class="topic-row">
      <span class="topic-row-avatar">
        <.category_mark :if={@lead == :category} category={@topic.category} />
        <UserComponents.avatar :if={@lead == :author} user={@topic.author} size={:list} />
      </span>
      <a href={~p"/t/#{@topic.id}/#{@topic.slug}"} class="topic-row-title">{@topic.title}</a>
      <span class="topic-row-badges">
        <span :if={@unread} class="badge badge-sm badge-primary unread-marker">
          {ngettext("1 new", "%{count} new", @unread)}
        </span>
        <span :if={@topic.pinned} class="badge badge-sm badge-ghost">
          <.icon name="hero-bookmark-micro" class="size-3" />{gettext("Pinned")}
        </span>
        <span :if={@topic.state == "archived"} class="badge badge-sm badge-ghost">
          {gettext("Archived")}
        </span>
        <span :if={@topic.state == "locked"} class="badge badge-sm badge-ghost">
          <.icon name="hero-lock-closed-micro" class="size-3" />{gettext("Locked")}
        </span>
      </span>
      <.tag_list :if={Ecto.assoc_loaded?(@topic.tags)} tags={@topic.tags} class="topic-row-tags" />
      <p class="topic-row-meta">
        <a :if={@lead == :category} href={~p"/c/#{@topic.category.slug}"} class="topic-category">
          {@topic.category.name}
        </a>
        <a
          :if={@lead == :author && @category}
          href={~p"/c/#{@topic.category.slug}"}
          class="topic-category"
        >
          <.category_mark category={@topic.category} />
          {@topic.category.name}
        </a>
        <span :if={@lead == :author && @category} aria-hidden="true">·</span>
        <span :if={@lead == :author} class="topic-starter">{@topic.author.display_name}</span>
        <span aria-hidden="true">·</span>
        <span>
          {gettext("last activity")} <.time_ago at={@topic.last_activity_at} />
        </span>
      </p>
      <p class="topic-row-count">
        <.icon name="hero-chat-bubble-left-right" class="size-4" />
        <span class="topic-messages">
          {ngettext("1 message", "%{count} messages", @topic.message_count)}
        </span>
      </p>
    </li>
    """
  end

  @doc """
  A topic's tags (TP-19), each a link to "Filter by tag" with that tag chosen. Nothing when
  there are none. Not a list of `<li>`s, so `li > a` in a topic list still finds titles only.
  """
  attr :tags, :list, required: true
  attr :class, :string, default: nil

  def tag_list(assigns) do
    ~H"""
    <p :if={@tags != []} class={["tag-list", @class]}>
      <span class="sr-only">{gettext("Tags:")}</span>
      <a :for={tag <- @tags} href={tag_path([tag])} class="tag-chip">{tag.name}</a>
    </p>
    """
  end

  @doc "The \"Filter by tag\" page with these tags chosen."
  @spec tag_path([map()]) :: String.t()
  def tag_path(tags), do: ~p"/tags?#{%{"tags" => Enum.map(tags, & &1.slug)}}"

  @doc """
  A time as how long ago it was ("5 min ago"), with the exact time in `datetime` and as a
  tooltip. Worked out when the page renders. `short` gives "5m", "3h", "2d".
  """
  attr :at, DateTime, required: true
  attr :short, :boolean, default: false

  def time_ago(assigns) do
    assigns =
      assign(assigns,
        text: ago(assigns.at, assigns.short),
        exact: Calendar.strftime(assigns.at, "%Y-%m-%d %H:%M UTC")
      )

    ~H"""
    <time datetime={DateTime.to_iso8601(@at)} title={@exact}>{@text}</time>
    """
  end

  defp ago(at, short?) do
    seconds = max(DateTime.diff(DateTime.utc_now(), at), 0)

    cond do
      seconds < 60 -> if short?, do: gettext("now"), else: gettext("just now")
      seconds < 3600 -> unit(div(seconds, 60), :minute, short?)
      seconds < 86_400 -> unit(div(seconds, 3600), :hour, short?)
      seconds < 30 * 86_400 -> unit(div(seconds, 86_400), :day, short?)
      true -> Calendar.strftime(at, "%Y-%m-%d")
    end
  end

  defp unit(n, :minute, true), do: gettext("%{n}m", n: n)
  defp unit(n, :hour, true), do: gettext("%{n}h", n: n)
  defp unit(n, :day, true), do: gettext("%{n}d", n: n)
  defp unit(n, :minute, false), do: ngettext("1 min ago", "%{count} min ago", n)
  defp unit(n, :hour, false), do: ngettext("1 hour ago", "%{count} hours ago", n)
  defp unit(n, :day, false), do: ngettext("yesterday", "%{count} days ago", n)
end

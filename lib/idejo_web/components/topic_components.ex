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

  alias Idejo.Forum.CategoryIcons
  alias IdejoWeb.UserComponents

  @hues 8

  @doc """
  A category's mark (decorative; the name is always next to it):

    * with an icon (RP-03), the icon on a tile of the category's colour, or of the tint its id
      gives it;
    * with a colour but no icon, its initial on a tile of that colour;
    * with neither, its initial on one of #{@hues} tints, picked from its id so it never
      changes.

  Colours are SVG `fill` attributes or classes, never `style` (SP-05).
  """
  attr :category, :map, required: true
  attr :size, :atom, values: [:small, :large], default: :small

  def category_mark(%{category: %{icon: icon} = category} = assigns) when is_binary(icon) do
    colour = Map.get(category, :colour) || CategoryIcons.tint(category.id)
    assigns = assign(assigns, :shapes, CategoryIcons.shapes(icon, colour))

    ~H"""
    <svg
      :if={@shapes}
      viewBox="0 0 32 32"
      class={["category-mark category-mark-svg", @size == :large && "category-mark-lg"]}
      aria-hidden="true"
      focusable="false"
    >
      <.icon_shapes shapes={@shapes} />
    </svg>
    """
  end

  def category_mark(%{category: %{colour: "#" <> _ = colour}} = assigns) do
    assigns = assign(assigns, colour: colour, ink: CategoryIcons.contrast(colour))

    ~H"""
    <svg
      viewBox="0 0 32 32"
      class={["category-mark category-mark-svg", @size == :large && "category-mark-lg"]}
      aria-hidden="true"
      focusable="false"
    >
      <rect width="32" height="32" rx="7" fill={@colour} />
      <text
        x="16"
        y="16.5"
        text-anchor="middle"
        dominant-baseline="central"
        font-size="16"
        font-weight="700"
        fill={@ink}
      >
        {initial(@category)}
      </text>
    </svg>
    """
  end

  def category_mark(assigns) do
    ~H"""
    <span
      class={["category-mark", "hue-#{hue(@category)}", @size == :large && "category-mark-lg"]}
      aria-hidden="true"
    >
      {initial(@category)}
    </span>
    """
  end

  defp initial(category), do: category.name |> String.first() |> String.upcase()

  @doc "An icon's shapes (`Idejo.Forum.CategoryIcons.shapes/2`), as SVG elements."
  attr :shapes, :list, required: true

  def icon_shapes(assigns) do
    ~H"""
    <.dynamic_tag :for={{tag, attrs, children} <- @shapes} tag_name={tag} {attrs}>
      <.icon_shapes shapes={children} />
    </.dynamic_tag>
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

  * `preview` - an expanded card (steward decision, 2026-10-23): `Idejo.Forum.topic_previews/1`
    for this topic, or nil for a compact one.

  Right click or long press opens the topic menu (`data-topic-menu`, `Layouts.topic_menu/1`).
  """
  attr :topic, :map, required: true
  attr :category, :boolean, default: false
  attr :lead, :atom, values: [:author, :category], default: :author
  attr :unread, :integer, default: nil
  attr :preview, :map, default: nil

  def topic_row(assigns) do
    ~H"""
    <li
      id={"topic-#{@topic.id}"}
      class={["topic-row", "cat-#{@topic.category_id}", @preview && "is-expanded"]}
      data-topic-menu={@topic.id}
      data-topic-path={~p"/t/#{@topic.id}/#{@topic.slug}"}
    >
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
      <.topic_preview :if={@preview} topic={@topic} preview={@preview} />
    </li>
    """
  end

  attr :topic, :map, required: true
  attr :preview, :map, required: true

  # An expanded card's body (steward decision, 2026-10-23): the opening message's text, with
  # its first image at the right; "Latest messages" over a line and the last three; and the
  # avatars of who wrote there, five and "+N more" past six.
  defp topic_preview(assigns) do
    %{participants: people, participant_count: count} = assigns.preview
    shown = if count > 6, do: Enum.take(people, 5), else: people

    assigns = assign(assigns, shown: shown, more: count - length(shown))

    ~H"""
    <div class="topic-preview">
      <div :if={@preview.first} class="topic-preview-first">
        <p class="topic-preview-text">{Idejo.Forum.excerpt(@preview.first, 400)}</p>
        <img
          :if={@preview.image}
          src={@preview.image}
          alt=""
          class="topic-preview-image"
          loading="lazy"
        />
      </div>
      <div :if={@preview.latest != []} class="topic-preview-latest">
        <%!-- Not a heading: the category page's list sits right under its h1 (AX-01). --%>
        <p class="topic-preview-heading">{gettext("Latest messages")}</p>
        <ol>
          <li :for={message <- @preview.latest} class="topic-preview-message">
            <UserComponents.avatar user={message.author} size={:small} />
            <a href={~p"/m/#{message.id}"} class="topic-preview-message-link">
              <span class="font-medium">{message.author.display_name}</span>
              <span class="topic-preview-message-text">{Idejo.Forum.excerpt(message, 160)}</span>
            </a>
            <.time_ago at={message.opened_at} />
          </li>
        </ol>
      </div>
      <p :if={@shown != []} class="topic-preview-people">
        <span class="sr-only">{gettext("Written by:")}</span>
        <span :for={user <- @shown} class="topic-preview-person" title={user.display_name}>
          <UserComponents.avatar user={user} size={:small} />
          <span class="sr-only">{user.display_name}</span>
        </span>
        <span :if={@more > 0} class="topic-preview-more">
          {ngettext("+%{count} more", "+%{count} more", @more)}
        </span>
      </p>
    </div>
    """
  end

  attr :view, :atom, required: true, values: [:compact, :expanded]
  attr :path, :string, required: true, doc: "the page's address, without ?view="

  @doc """
  The "View" toggle of the home and category pages (steward decision, 2026-10-23): Compact
  (the default) or Expanded topic cards. Two links, so it works without JavaScript;
  `IdejoWeb.TopicView` remembers the choice.
  """
  def view_toggle(assigns) do
    ~H"""
    <nav aria-label={gettext("View")} class="view-toggle" id="view-toggle">
      <span class="view-toggle-label" aria-hidden="true">{gettext("View")}</span>
      <a
        :for={{view, label} <- [compact: gettext("Compact"), expanded: gettext("Expanded")]}
        href={with_view(@path, view)}
        id={"view-#{view}"}
        aria-current={@view == view && "true"}
        class={@view == view && "is-active"}
      >
        {label}
      </a>
    </nav>
    """
  end

  defp with_view(path, view) do
    %URI{query: query} = uri = URI.parse(path)
    params = URI.decode_query(query || "") |> Map.put("view", Atom.to_string(view))
    URI.to_string(%{uri | query: URI.encode_query(params)})
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

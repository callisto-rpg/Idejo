# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use IdejoWeb, :html

  alias Idejo.Forum.CategoryIcons
  alias Idejo.Push
  alias Idejo.Push.Vapid

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :width, :atom,
    values: [:narrow, :wide],
    default: :narrow,
    doc: "the content column: narrow for reading, wide for grids and tables"

  attr :category, :any, default: nil, doc: "the category shown, marked in the sidebar"

  attr :topic, :any,
    default: nil,
    doc: "the topic shown: highlighted in the sidebar, and listed there even when not followed"

  attr :push_banner, :boolean,
    default: false,
    doc: "offer browser notifications (PN-20: category and topic pages, `Push.banner?/1`)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :user, assigns.current_scope && assigns.current_scope.user)

    ~H"""
    <header class="app-header">
      <%!-- Shown and wired by assets/js/sidebar.js: without JavaScript the sidebar stays
           open on wide screens, and the home page lists the categories anyway. --%>
      <button
        type="button"
        id="sidebar-toggle"
        class="sidebar-toggle btn btn-ghost btn-sm btn-square"
        aria-controls="sidebar"
        aria-expanded="true"
        aria-label={gettext("Show or hide the categories")}
      >
        <.icon name="hero-bars-3" class="size-5" />
      </button>

      <a href={~p"/"} class="brand" id="brand">
        <%!-- The small Idejo logo, before the server's own name (steward decision, 2026-10-23). --%>
        <img src={~p"/images/logo-small.svg"} alt="" class="brand-mark" width="32" height="32" />
        <span class="brand-name">{server_name()}</span>
      </a>

      <form action={~p"/search"} method="get" role="search" class="header-search">
        <label for="header-search-q" class="sr-only">{gettext("Search")}</label>
        <.icon name="hero-magnifying-glass" class="size-4 header-search-icon" />
        <input
          type="search"
          name="q"
          id="header-search-q"
          placeholder={gettext("Search")}
          class="header-search-input"
        />
      </form>

      <nav aria-label={gettext("Site")} class="header-nav">
        <a
          href={~p"/search"}
          id="search-link"
          class="header-icon md:hidden"
          aria-label={gettext("Search")}
        >
          <.icon name="hero-magnifying-glass" class="size-5" />
        </a>
        <.unread_link :if={@user} user={@user} />
        <.moderation_link :if={@user} user={@user} />
      </nav>

      <.account_menu current_scope={@current_scope} />
    </header>

    <div class="app-body">
      <.sidebar user={@user} current={@category} topic={@topic} />

      <div class="app-column">
        <div
          :if={@user && !Idejo.Accounts.confirmed?(@user)}
          role="status"
          class="verify-banner"
        >
          <.icon name="hero-envelope" class="size-5 shrink-0" />
          <p class="grow">
            {gettext("Please verify your email address to take part. Check your inbox for the link.")}
          </p>
          <.form for={%{}} action={~p"/users/confirm"}>
            <button class="btn btn-sm">{gettext("Send the link again")}</button>
          </.form>
        </div>

        <.push_banner :if={@push_banner} />

        <%!-- AX-01: the skip link's target; tabindex lets it take the focus in every browser. --%>
        <main id="main" tabindex="-1" class="app-main focus:outline-none">
          <div class={["mx-auto space-y-6", width_class(@width)]}>
            {render_slot(@inner_block)}
          </div>
        </main>

        <.site_footer />
      </div>
    </div>

    <.flash_group flash={@flash} />
    <.welcome_card :if={@user && is_nil(@user.welcomed_at)} user={@user} />
    <.topic_menu :if={@user} user={@user} />
    """
  end

  @doc """
  The topic menu (steward decision, 2026-10-23): right click or long press on a topic in a
  list or in the sidebar (`data-topic-menu`, `data-topic-path`) opens it there
  (`assets/js/topic_menu.js`, which fills in the topic's addresses): Follow or Unfollow
  (from the sidebar's `data-following`), Unfollow & mute, Mark unread and Copy link. Plain
  forms with `return=back` to `FollowController`; hidden until a script opens it.

  Moderators (`:moderate` in some category; owners and administrators always) also get
  (steward decisions, 2026-11-01), filled in from `GET /topic-menu/{id}`
  (`TopicMenuController`) when it opens, only for topics of categories they moderate: "N following", which a click
  turns red as "Mark as inactive" and a second click posts (`Forum.mark_inactive/2`), then
  Archive, "Move to" (the categories they moderate, the topic's own left out) and Delete (a second click
  confirms); on an archived topic, "Unarchive to {category}" (where it was archived from)
  or, without one, "Unarchive to…" over the same category list, all posted to `/t/{id}/moderate` (`TopicModerationController`) with
  `return=back`.

  Like every menu, it is a `.popup-menu`: see-through and blurred, set by the server
  stylesheet's `--menu-opacity` and `--menu-blur` (`priv/theme/default.css`).
  """
  attr :user, :map, required: true

  def topic_menu(assigns) do
    assigns =
      assign(assigns, :move_categories, Idejo.Forum.list_moderated_categories(assigns.user))

    ~H"""
    <div
      id="topic-menu"
      class="popup-menu topic-menu has-arrow"
      role="menu"
      aria-label={gettext("Topic")}
      phx-update="ignore"
      hidden
    >
      <.form
        for={%{}}
        action="/t/:id/follow"
        method="delete"
        data-action="/follow"
        id="topic-menu-unfollow"
      >
        <input type="hidden" name="return" value="back" />
        <button role="menuitem" tabindex="-1">
          <.icon name="hero-x-mark" class="size-4" />{gettext("Unfollow")}
        </button>
      </.form>
      <.form for={%{}} action="/t/:id/follow" data-action="/follow" id="topic-menu-follow">
        <input type="hidden" name="return" value="back" />
        <button role="menuitem" tabindex="-1">
          <.icon name="hero-plus" class="size-4" />{gettext("Follow")}
        </button>
      </.form>
      <.form for={%{}} action="/t/:id/mute" data-action="/mute" id="topic-menu-mute">
        <input type="hidden" name="return" value="back" />
        <button role="menuitem" tabindex="-1">
          <.icon name="hero-bell-slash" class="size-4" />{gettext("Unfollow & mute")}
        </button>
      </.form>
      <.form for={%{}} action="/t/:id/unread" data-action="/unread" id="topic-menu-unread">
        <input type="hidden" name="return" value="back" />
        <button role="menuitem" tabindex="-1">
          <.icon name="hero-envelope" class="size-4" />{gettext("Mark unread")}
        </button>
      </.form>
      <button
        type="button"
        role="menuitem"
        tabindex="-1"
        id="topic-menu-link"
        data-copied={gettext("Link copied")}
      >
        <.icon name="hero-link" class="size-4" /><span class="topic-menu-label">{gettext("Copy link")}</span>
      </button>
      <div :if={@move_categories != []} id="topic-menu-admin" class="topic-menu-admin" hidden>
        <hr role="separator" />
        <.form
          for={%{}}
          action="/t/:id/moderate"
          data-action="/moderate"
          id="topic-menu-inactive"
        >
          <input type="hidden" name="action" value="inactive" />
          <input type="hidden" name="return" value="back" />
          <button
            role="menuitem"
            tabindex="-1"
            id="topic-menu-following"
            data-one={gettext("1 following")}
            data-many={
              # The script puts the count in: the placeholder passes through as is.
              gettext("%{count} following", count: "%{count}")
            }
            data-inactive={gettext("inactive")}
            data-confirm-label={gettext("Mark as inactive")}
          >
            <.icon name="hero-users" class="size-4" /><span class="topic-menu-label">{gettext(
              "… following"
            )}</span>
          </button>
        </.form>
        <.form
          for={%{}}
          action="/t/:id/moderate"
          data-action="/moderate"
          id="topic-menu-archive"
        >
          <input type="hidden" name="action" value="archive" />
          <input type="hidden" name="return" value="back" />
          <button role="menuitem" tabindex="-1">
            <.icon name="hero-archive-box" class="size-4" />{gettext("Archive")}
          </button>
        </.form>
        <.form
          for={%{}}
          action="/t/:id/moderate"
          data-action="/moderate"
          id="topic-menu-unarchive"
          hidden
        >
          <input type="hidden" name="action" value="unarchive" />
          <input type="hidden" name="return" value="back" />
          <button
            role="menuitem"
            tabindex="-1"
            data-label={
              # The script puts the category's name in.
              gettext("Unarchive to %{category}", category: "%{category}")
            }
          >
            <.icon name="hero-arrow-uturn-left" class="size-4" /><span class="topic-menu-label">{gettext(
              "Unarchive"
            )}</span>
          </button>
        </.form>
        <button
          type="button"
          role="menuitem"
          tabindex="-1"
          id="topic-menu-unarchive-toggle"
          class="topic-menu-list-toggle"
          aria-expanded="false"
          aria-controls="topic-menu-move"
          data-list-action="unarchive"
          hidden
        >
          <.icon name="hero-arrow-uturn-left" class="size-4" />{gettext("Unarchive to…")}
        </button>
        <button
          type="button"
          role="menuitem"
          tabindex="-1"
          id="topic-menu-move-toggle"
          class="topic-menu-list-toggle"
          data-list-action="move"
          aria-expanded="false"
          aria-controls="topic-menu-move"
        >
          <.icon name="hero-arrow-right-circle" class="size-4" />{gettext("Move to…")}
        </button>
        <.form
          for={%{}}
          action="/t/:id/moderate"
          data-action="/moderate"
          id="topic-menu-move"
          class="topic-menu-move"
          hidden
        >
          <input type="hidden" name="action" value="move" id="topic-menu-move-action" />
          <input type="hidden" name="return" value="back" />
          <button
            :for={category <- @move_categories}
            role="menuitem"
            tabindex="-1"
            name="category_id"
            value={category.id}
            data-category-id={category.id}
          >
            {category.name}
          </button>
        </.form>
        <.form
          for={%{}}
          action="/t/:id/moderate"
          data-action="/moderate"
          id="topic-menu-delete"
        >
          <input type="hidden" name="action" value="delete" />
          <input type="hidden" name="confirm" value="yes" />
          <input type="hidden" name="return" value="back" />
          <button role="menuitem" tabindex="-1" data-confirm-label={gettext("Delete for good")}>
            <.icon name="hero-trash" class="size-4" /><span class="topic-menu-label">{gettext(
              "Delete"
            )}</span>
          </button>
        </.form>
      </div>
    </div>
    """
  end

  attr :user, :map, required: true

  # The welcome card (steward decision, 2026-10-23): over the page on a new member's first
  # visit, until they continue (`POST /welcome`). Shown without JavaScript too.
  defp welcome_card(assigns) do
    assigns = assign(assigns, :data, IdejoWeb.WelcomeComponents.welcome_data(assigns.user))

    ~H"""
    <div
      id="welcome-card"
      class="welcome-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="welcome-title"
    >
      <div class="welcome-card">
        <h2 id="welcome-title" class="welcome-title">
          {gettext("Welcome to %{server}", server: server_name())}
        </h2>
        <IdejoWeb.WelcomeComponents.welcome_content
          data={@data}
          heading="h3"
          submit={gettext("Continue")}
        />
      </div>
    </div>
    """
  end

  defp width_class(:narrow), do: "max-w-3xl"
  defp width_class(:wide), do: "max-w-5xl"

  attr :current_scope, :map, required: true

  # The account menu: a <details> disclosure, so it opens without JavaScript.
  defp account_menu(assigns) do
    ~H"""
    <nav aria-label={gettext("Account")} class="account-nav">
      <%= if @current_scope && @current_scope.user do %>
        <details class="account-menu" id="account-menu">
          <summary class="account-summary">
            <IdejoWeb.UserComponents.avatar user={@current_scope.user} size={:small} />
            <span class="account-name">{@current_scope.user.display_name}</span>
            <.icon name="hero-chevron-down-micro" class="size-4 opacity-60" />
          </summary>
          <div class="account-panel popup-menu has-arrow arrow-right">
            <p class="account-panel-who">
              <span class="font-medium">{@current_scope.user.display_name}</span>
              <span class="opacity-60">@{@current_scope.user.username}</span>
            </p>
            <ul>
              <li>
                <.link href={~p"/users/settings"} id="settings-link">
                  <.icon name="hero-user-circle" class="size-4" />
                  {gettext("Profile and account")}
                </.link>
              </li>
              <li :if={@current_scope.administrator?}>
                <.link href={~p"/admin"} id="admin-link">
                  <.icon name="hero-cog-6-tooth" class="size-4" />
                  {gettext("Admin")}
                </.link>
              </li>
              <li class="account-panel-theme">
                <span>{gettext("Theme")}</span>
                <.theme_toggle />
              </li>
              <li class="account-panel-theme bubbles-toggle-row">
                <span id="account-bubbles-label">{gettext("Tutorial bubbles")}</span>
                <.bubbles_toggle labelled_by="account-bubbles-label" />
              </li>
              <li>
                <%!-- A form, not a data-method link, so signing out works without JavaScript. --%>
                <.form for={%{}} action={~p"/users/sign-out"} method="delete">
                  <button>
                    <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
                    {gettext("Sign out")}
                  </button>
                </.form>
              </li>
            </ul>
          </div>
        </details>
      <% else %>
        <%!-- On phones, the sidebar holds it: the header has no room. --%>
        <.theme_toggle class="max-sm:hidden" />
        <.link href={~p"/users/sign-in"} class="btn btn-ghost btn-sm">{gettext("Sign in")}</.link>
        <.link href={~p"/users/sign-up"} class="btn btn-primary btn-sm">
          {gettext("Sign up")}
        </.link>
      <% end %>
    </nav>
    """
  end

  attr :user, :any, required: true
  attr :current, :any, required: true, doc: "the category shown (only its `id` is read), or nil"

  attr :topic, :any,
    default: nil,
    doc: "the topic shown (`id`, `title`, `slug`, `category_id`), or nil"

  @doc """
  The sidebar: the categories the visitor may view, in their order and groups, each with the
  topics the user follows in it (TP-13), oldest followed first. Hidden and shown by the
  header's button (assets/js/sidebar.js), which the browser remembers. Also served alone at
  `/sidebar` (`SidebarController`), which the `Notifier` hook fetches to bring it up to date
  without a page load (steward decision, 2026-10-23).

  The topic on screen is highlighted, never folded under "more topics", and listed under
  its category for a signed-in user even when they do not follow it, with a "+" to follow
  it where a followed topic has its "×" (steward decision, 2026-10-23).
  """
  def sidebar(assigns) do
    # In the home page's order, in the same sections (RP-03).
    summaries = Idejo.Forum.list_category_summaries(assigns.user)
    sections = Idejo.Forum.sections(summaries, Idejo.Forum.list_groups())

    followed_topics = Idejo.Reading.list_followed_topics(assigns.user)
    following = MapSet.new(followed_topics, & &1.id)
    topic = assigns.topic

    # The topic on screen, last under its category, when the user does not follow it.
    listed =
      if assigns.user && topic && not MapSet.member?(following, topic.id),
        do: followed_topics ++ [topic],
        else: followed_topics

    # What is new in each followed topic: its dot (steward decision, 2026-10-23).
    activity = Idejo.Reading.activity(assigns.user, MapSet.to_list(following))

    assigns =
      assign(assigns,
        summaries: summaries,
        sections: sections,
        followed: Enum.group_by(listed, & &1.category_id),
        activity: activity,
        place: %{topic_id: topic && topic.id, following: following, user?: assigns.user != nil},
        conversations_unread: Idejo.Conversations.unread_count(assigns.user)
      )

    ~H"""
    <aside
      id="sidebar"
      class="app-sidebar"
      data-category={@current && @current.id}
      data-topic={@place.topic_id}
    >
      <nav aria-label={gettext("Categories")} class="sidebar-nav">
        <%!-- These links first, above the categories (steward decision, 2026-10-23). --%>
        <%!-- The button at the right of All categories rolls the other links up into their
             icons, beside it, and down again (steward decision, 2026-10-28; sidebar.js,
             remembered and applied before paint by theme.js). Without scripts it is hidden
             and the links show in full. Rolled, All categories reads "All", to take less
             room, its full name kept for screen readers (steward decision, 2026-11-01). --%>
        <div class="sidebar-quicklinks" id="sidebar-quicklinks">
          <a href={~p"/"} class="sidebar-link sidebar-all">
            <.icon name="hero-squares-2x2" class="size-4" />
            <span class="sidebar-all-label">{gettext("All categories")}</span>
            <span class="sidebar-all-rolled" aria-hidden="true">{pgettext("categories", "All")}</span>
          </a>
          <div id="sidebar-quicklinks-more" class="sidebar-quicklinks-more">
            <%!-- TP-19 --%>
            <a
              href={~p"/tags"}
              class="sidebar-link"
              id="tags-link"
              data-bubble={gettext("Filter by tag")}
            >
              <.icon name="hero-tag" class="size-4" />
              <span class="sidebar-link-label">{gettext("Filter by tag")}</span>
            </a>
            <%!-- The server's About, Rules and self-select roles (steward decision,
                 2026-10-23). --%>
            <a
              href={~p"/rules"}
              class="sidebar-link"
              id="rules-link"
              data-bubble={gettext("Rules & Roles")}
            >
              <.icon name="hero-book-open" class="size-4" />
              <span class="sidebar-link-label">{gettext("Rules & Roles")}</span>
            </a>
            <%!-- The keys, the signs and the ! commands (steward decision, 2026-10-23). --%>
            <a
              href={~p"/help"}
              class="sidebar-link"
              id="help-link"
              data-bubble={gettext("Help")}
            >
              <.icon name="hero-question-mark-circle" class="size-4" />
              <span class="sidebar-link-label">{gettext("Help")}</span>
            </a>
          </div>
          <button
            type="button"
            id="sidebar-quicklinks-roll"
            class="sidebar-roll"
            aria-pressed="false"
            aria-controls="sidebar-quicklinks-more"
            aria-label={gettext("Show these links as icons only")}
            data-bubble={gettext("Icons only")}
            data-bubble-folded={gettext("Show the links' names")}
          ></button>
        </div>
        <%= case @sections do %>
          <% [{_group, only}] -> %>
            <p class="sidebar-heading">{gettext("Categories")}</p>
            <.sidebar_categories
              summaries={only}
              current={@current}
              followed={@followed}
              activity={@activity}
              place={@place}
            />
          <% several -> %>
            <%!-- RP-03: one section per group, ungrouped last. Groups do not fold; categories
                 do (steward decision, 2026-10-23). --%>
            <div
              :for={{group, items} <- several}
              id={"sidebar-group-#{if group, do: group.id, else: "other"}"}
              class="sidebar-group"
            >
              <p class="sidebar-heading sidebar-group-title">
                {if group, do: group.name, else: gettext("Other")}
              </p>
              <.sidebar_categories
                summaries={items}
                current={@current}
                followed={@followed}
                activity={@activity}
                place={@place}
              />
            </div>
        <% end %>
        <p :if={@summaries == []} class="sidebar-empty">{gettext("No categories yet.")}</p>
      </nav>
      <div :if={!@user} class="sidebar-theme sm:hidden">
        <span>{gettext("Theme")}</span>
        <.theme_toggle />
      </div>
      <%!-- Pinned at the very bottom (steward decision, 2026-10-27), with how many
           conversations have something new. --%>
      <div :if={@user} class="sidebar-pinned">
        <a href={~p"/p"} class="sidebar-link" id="conversations-sidebar-link">
          <.icon name="hero-chat-bubble-left-right" class="size-4" />
          {gettext("Private Conversations")}
          <span :if={@conversations_unread > 0} class="sidebar-count">
            {@conversations_unread}<span class="sr-only">{ngettext(
              " conversation with new messages",
              " conversations with new messages",
              @conversations_unread
            )}</span>
          </span>
        </a>
      </div>
    </aside>
    """
  end

  attr :summaries, :list, required: true
  attr :current, :any, required: true
  attr :followed, :map, required: true
  attr :activity, :map, default: %{}
  attr :place, :map, required: true, doc: "`topic_id` (the topic on screen), `following`"

  # The categories of one section of the sidebar, each with the topics the user follows there.
  # A category with topics has a fold button (steward decision, 2026-10-23; sidebar.js, which
  # remembers it): folded, only its topics with something new show, and the one on screen.
  defp sidebar_categories(assigns) do
    ~H"""
    <ul>
      <li
        :for={%{category: category} = summary <- @summaries}
        class="sidebar-category"
        data-category-id={category.id}
      >
        <div class="sidebar-category-row">
          <a
            href={~p"/c/#{category.slug}"}
            class={[
              "sidebar-link",
              "cat-#{category.id}",
              @current && @current.id == category.id && "is-current"
            ]}
            aria-current={@current && @current.id == category.id && "page"}
          >
            <IdejoWeb.TopicComponents.category_mark category={category} size={:small} />
            <span class="sidebar-name">{category.name}</span>
            <span :if={summary.last_activity_at} class="sidebar-when">
              <IdejoWeb.TopicComponents.time_ago at={summary.last_activity_at} short />
            </span>
          </a>
          <button
            :if={Map.get(@followed, category.id, []) != []}
            type="button"
            class="sidebar-fold"
            aria-pressed="false"
            aria-controls={"sidebar-topics-#{category.id}"}
            aria-label={gettext("Only topics with new messages in %{name}", name: category.name)}
            data-bubble={gettext("Hide topics with\nno new messages")}
            data-bubble-folded={gettext("Show all followed topics")}
          ></button>
        </div>
        <.followed_topics
          id={"sidebar-topics-#{category.id}"}
          topics={Map.get(@followed, category.id, [])}
          activity={@activity}
          place={@place}
        />
      </li>
    </ul>
    """
  end

  attr :id, :string, required: true
  attr :topics, :list, required: true
  attr :activity, :map, default: %{}
  attr :place, :map, required: true

  @followed_shown 4

  # The topics followed in one category: the first four, then the rest behind a "more topics"
  # disclosure (a <details>, so it opens without JavaScript). The topic on screen is always
  # among those shown.
  defp followed_topics(assigns) do
    {shown, more} = Enum.split(assigns.topics, @followed_shown)

    {shown, more} =
      case Enum.split_with(more, &(&1.id == assigns.place.topic_id)) do
        {[on_screen], rest} -> {shown ++ [on_screen], rest}
        _ -> {shown, more}
      end

    assigns = assign(assigns, shown: shown, more: more)

    ~H"""
    <ul :if={@topics != []} id={@id} class="sidebar-topics">
      <.followed_topic
        :for={topic <- @shown}
        topic={topic}
        activity={@activity[topic.id]}
        place={@place}
      />
      <li :if={@more != []} class="sidebar-more-item">
        <details id={"sidebar-more-#{hd(@more).category_id}"} class="sidebar-more">
          <summary>
            <span class="sidebar-more-closed">
              {ngettext("1 more topic", "%{count} more topics", length(@more))}
            </span>
            <span class="sidebar-more-open">{gettext("Fewer topics")}</span>
          </summary>
          <ul class="sidebar-topics">
            <.followed_topic
              :for={topic <- @more}
              topic={topic}
              activity={@activity[topic.id]}
              place={@place}
            />
          </ul>
        </details>
      </li>
    </ul>
    """
  end

  attr :topic, :map, required: true

  attr :activity, :atom,
    default: nil,
    doc: "nil, :new, :role_mention, :reply or :mention (Reading.activity/2)"

  attr :place, :map, required: true

  # One topic: followed, with an "×" to unfollow it (TP-13), or the topic on screen, not
  # followed, with a "+" to follow it. Plain form posts: FollowController leads back to the
  # page they came from. Something new there shows as a dot, grey, blue for a mention of one
  # of the user's roles, orange for a reply to the user, red for a mention of them, and a
  # stronger name. The topic on screen is highlighted; a new message there makes its name
  # glow (the Notifier hook, `data-topic-id`).
  defp followed_topic(assigns) do
    assigns =
      assign(assigns,
        on_screen?: assigns.topic.id == assigns.place.topic_id,
        following?: MapSet.member?(assigns.place.following, assigns.topic.id)
      )

    ~H"""
    <li
      class={["sidebar-topic", @activity && "has-news", @on_screen? && "is-current"]}
      data-topic-id={@topic.id}
      data-topic-menu={@place.user? && @topic.id}
      data-topic-path={~p"/t/#{@topic.id}/#{@topic.slug}"}
      data-following={@following? && "true"}
    >
      <span
        class={["sidebar-dot", @activity && "is-#{String.replace(to_string(@activity), "_", "-")}"]}
        aria-hidden="true"
      ></span>
      <a
        href={~p"/t/#{@topic.id}/#{@topic.slug}"}
        class="sidebar-topic-link"
        aria-current={@on_screen? && "page"}
        title={@topic.title}
      >
        <span class="sidebar-topic-name">{@topic.title}</span><span
          :if={@activity}
          class="sr-only"
        >{activity_text(@activity)}</span>
      </a>
      <%!-- Visitors see the topics followed by everyone, with nothing to follow or unfollow. --%>
      <.form
        :if={@place.user? && @following?}
        for={%{}}
        action={~p"/t/#{@topic.id}/follow"}
        method="delete"
        class="sidebar-topic-action sidebar-unfollow"
      >
        <input type="hidden" name="return" value="back" />
        <%!-- Its tutorial bubble (steward decision, 2026-10-25), at its right on hover or
             focus, and for a moment on touch screens (assets/js/sidebar.js). --%>
        <button
          type="submit"
          aria-label={gettext("Unfollow %{title}", title: @topic.title)}
          data-bubble={gettext("close & unfollow thread")}
        >
          <.icon name="hero-x-mark-micro" class="size-3.5" />
        </button>
      </.form>
      <.form
        :if={@place.user? && !@following?}
        for={%{}}
        action={~p"/t/#{@topic.id}/follow"}
        method="post"
        class="sidebar-topic-action sidebar-follow"
      >
        <input type="hidden" name="return" value="back" />
        <button
          type="submit"
          aria-label={gettext("Follow %{title}", title: @topic.title)}
          title={gettext("Follow")}
        >
          <.icon name="hero-plus-micro" class="size-3.5" />
        </button>
      </.form>
    </li>
    """
  end

  defp activity_text(:new), do: gettext(" (new messages)")
  defp activity_text(:role_mention), do: gettext(" (one of your roles was mentioned)")
  defp activity_text(:reply), do: gettext(" (a reply to you)")
  defp activity_text(:mention), do: gettext(" (you were mentioned)")

  attr :nonce, :string, default: nil
  attr :user, :any, default: nil
  attr :info_boxes, :list, default: [], doc: "the page's info boxes (the home page's)"

  @doc """
  Each category's colour as a CSS variable, `--cat` on `.cat-{id}`, for the lines and glows
  of the elements that belong to it (RP-03): its own colour, or the tint its id gives it. Only
  the categories the visitor may view, so no other id reaches the page (AC-05). The page's
  info boxes (steward decision, 2026-10-25) get theirs the same way, on `.info-box-{id}`. A
  `<style>` with the request's nonce: the CSP refuses `style` attributes (SP-05); the colours
  are checked `#rrggbb` and the ids UUIDs, so the rules hold nothing else.
  """
  def category_colours(assigns) do
    categories =
      for category <- Idejo.Forum.list_viewable_categories(assigns.user), into: "" do
        colour = category.colour || CategoryIcons.tint(category.id)
        ".cat-#{category.id}{--cat:#{colour}}"
      end

    rules =
      for box <- assigns.info_boxes, into: categories do
        ".info-box-#{box.id}{--cat:#{box.colour || CategoryIcons.tint(box.id)}}"
      end

    assigns = assign(assigns, :rules, rules)

    ~H"""
    <style :if={@nonce && @rules != ""} nonce={@nonce}>
      <%= @rules %>
    </style>
    """
  end

  @doc """
  The website theme (steward decision, 2026-10-24; Admin → Settings): the daisyUI colour
  variables of both themes from `Idejo.Settings.theme/0`, in one `<style>` with the
  request's nonce, before the server stylesheet so Admin → Stylesheet can still override it.
  Primary drives buttons, toggles and links; secondary and tertiary (daisyUI's secondary and
  accent) only where a second colour distinguishes or unemphasises. The page background is
  the light or dark background, cards a little lighter, and text the other background. Text
  on a colour is white or near-black, whichever contrasts better. The colours are checked
  `#rrggbb` or `#rrggbbaa`, so the rules hold nothing else.
  """
  attr :nonce, :string, default: nil

  def theme_colours(assigns) do
    assigns = assign(assigns, :rules, theme_rules(Idejo.Settings.theme()))

    ~H"""
    <style :if={@nonce} nonce={@nonce}>
      <%= @rules %>
    </style>
    """
  end

  @doc false
  def theme_rules(%{light_bg: light, dark_bg: dark} = theme) do
    accents = accent_variables(theme)

    light_vars =
      accents <>
        "--color-base-100:color-mix(in oklab,#{light} 35%,#fff);" <>
        "--color-base-200:#{light};" <>
        "--color-base-300:color-mix(in oklab,#{light} 91%,#000);" <>
        "--color-base-content:#{dark};"

    dark_vars =
      accents <>
        "--color-base-100:color-mix(in oklab,#{dark} 92%,#fff);" <>
        "--color-base-200:#{dark};" <>
        "--color-base-300:color-mix(in oklab,#{dark} 82%,#fff);" <>
        "--color-base-content:color-mix(in oklab,#{light} 92%,#{dark});"

    # The selectors match daisyUI's own (light by default, dark when chosen or, with no
    # choice, when the system prefers it), so these come after them and win.
    ":root,[data-theme=light]{#{light_vars}}" <>
      "@media (prefers-color-scheme:dark){:root:not([data-theme]){#{dark_vars}}}" <>
      "[data-theme=dark]{#{dark_vars}}"
  end

  defp accent_variables(%{primary: primary, secondary: secondary, tertiary: tertiary}) do
    for {name, colour} <- [primary: primary, secondary: secondary, accent: tertiary], into: "" do
      "--color-#{name}:#{colour};--color-#{name}-content:#{on_colour(colour)};"
    end
  end

  # White or near-black text on a colour; any alpha is ignored for the choice.
  defp on_colour(colour), do: CategoryIcons.contrast(String.slice(colour, 0, 7))

  @doc """
  The roles' colours (steward decision, 2026-10-23): `--role` on each `role-{id}` class, in
  one `<style>` carrying the request's nonce, for `IdejoWeb.Admin.role_label/1`. Roles are
  public (`/r/{slug}`), so every role with a colour is listed.
  """
  attr :nonce, :string, default: nil

  def role_colours(assigns) do
    rules =
      for %{colour: colour, id: id} when is_binary(colour) <- Idejo.Access.list_roles(),
          into: "",
          do: ".role-#{id}{--role:#{colour}}"

    assigns = assign(assigns, :rules, rules)

    ~H"""
    <style :if={@nonce && @rules != ""} nonce={@nonce}>
      <%= @rules %>
    </style>
    """
  end

  attr :user, :map, required: true

  @doc """
  The header's Unread link (TP-07: topics with something new, across categories), with a
  dot counting the unread messages that reply to the user or mention them or their roles,
  coloured like the sidebar's dots (`Idejo.Reading.for_you/1`; steward decision,
  2026-10-23). Also served in `/sidebar`, so the `Notifier` hook keeps it current.
  """
  def unread_link(assigns) do
    assigns = assign(assigns, :for_you, Idejo.Reading.for_you(assigns.user))

    ~H"""
    <a href={~p"/unread"} id="unread-link" class="header-link">
      <.icon name="hero-inbox-stack" class="size-5" />
      <span class="header-link-text">{gettext("Unread")}</span>
      <span
        :if={@for_you.count > 0}
        class={[
          "header-badge",
          "unread-badge",
          "is-#{String.replace(to_string(@for_you.level), "_", "-")}"
        ]}
      >
        {@for_you.count}<span class="sr-only">{ngettext(
          " reply or mention for you",
          " replies and mentions for you",
          @for_you.count
        )}</span>
      </span>
    </a>
    """
  end

  attr :user, :map, required: true

  # MO-01, MO-03: the Moderation screen, for users who may moderate somewhere, with the number
  # of reported messages waiting.
  defp moderation_link(assigns) do
    assigns = assign(assigns, :reports, Idejo.Moderation.open_report_count(assigns.user))

    ~H"""
    <a
      :if={Idejo.Moderation.moderator?(@user)}
      href={~p"/moderation"}
      id="moderation-link"
      class="header-link"
    >
      <.icon name="hero-shield-check" class="size-5" />
      <span class="header-link-text">{gettext("Moderation")}</span>
      <span :if={@reports > 0} class="header-badge header-badge-warning">
        {@reports}<span class="sr-only">{gettext(" open reports")}</span>
      </span>
    </a>
    """
  end

  @doc """
  The footer on every page: the attribution notice (LI-02), the "Source code" link (LI-03)
  and the privacy notice (AD-02).

  The notice is kept word for word as NOTICE gives it, and is not translated: section 7(b)
  of the licence requires it to be preserved.
  """
  def site_footer(assigns) do
    ~H"""
    <footer class="site-footer">
      <a href="https://idejo.org" id="attribution">
        Powered by Idejo — © Mariano Pictet and contributors — AGPL-3.0
      </a>
      <a href={Idejo.Source.url()} id="source-code">{gettext("Source code")}</a>
      <a href={~p"/privacy"} id="privacy-link">{gettext("Privacy")}</a>
    </footer>
    """
  end

  @doc """
  The full Idejo logo (steward decisions, 2026-10-23 and 2026-10-24), above the sign-in,
  sign-up and setup pages and on the visitors' card: in colour, the same in both themes.
  CC-BY-4.0, © Mariano Pictet (NOTICE); `/images/logo.png` is the same as a raster image.
  """
  def full_logo(assigns) do
    ~H"""
    <img src={~p"/images/logo.svg"} alt="Idejo" class="full-logo" width="199" height="105" />
    """
  end

  @doc """
  The name shown in the header and page titles: the server name set by an administrator
  (AD-02), or "Idejo" when none is set. The header shows it after the small Idejo logo.
  """
  @spec server_name() :: String.t()
  def server_name, do: Idejo.Settings.get(:server_name)

  @doc """
  The server's VAPID public key as `<meta name="push-key">`, for signed-in users while push
  is on (PN-18, PN-19): `assets/js/push.js` subscribes the browser with it. Nothing for
  visitors, so they never subscribe.
  """
  attr :current_scope, :any, default: nil

  def push_key(assigns) do
    assigns =
      assign(
        assigns,
        :key,
        signed_in?(assigns.current_scope) && Push.enabled?() &&
          Vapid.public_key()
      )

    ~H"""
    <meta :if={@key} name="push-key" content={@key} />
    """
  end

  defp signed_in?(%{user: %{}}), do: true
  defp signed_in?(_scope), do: false

  @doc """
  The notifications banner (PN-20 to PN-23): a slim bar in the page's flow under the header,
  so it never covers the composer. Rendered `hidden`; `assets/js/push_banner.js` shows it
  only while push is off in this browser and can be turned on (or, in an iPhone or iPad
  Safari tab, with how to add the site to the Home Screen instead of "Enable"). Its words
  and buttons, and the tutorial bubble under "Enable", are the steward's (2026-10-25). A named region, announced politely,
  never an alert; it never takes the focus.
  """
  def push_banner(assigns) do
    ~H"""
    <section
      id="push-banner"
      class="push-banner"
      role="region"
      aria-label={gettext("Notifications")}
      aria-live="polite"
      hidden
    >
      <.icon name="hero-bell" class="size-5 shrink-0" />
      <p class="push-banner-offer grow">
        {gettext("Push notifications not enabled. You will not be notified of new messages.")}
      </p>
      <p class="push-banner-ios grow" hidden>
        {gettext(
          "To get notifications on iPhone, add Idejo to your Home Screen: tap Share, then Add to Home Screen, then open it from there."
        )}
      </p>
      <p class="push-banner-on grow" hidden>{gettext("Notifications are on")}</p>
      <div class="push-banner-actions">
        <%!-- With a tutorial bubble under it (steward decision, 2026-10-25), in the banner's
             flow so it covers nothing; the Tutorial bubbles toggle hides it. --%>
        <span class="push-banner-enable">
          <button type="button" class="btn btn-sm btn-primary push-banner-turn-on">
            {gettext("Enable")}
          </button>
          <span class="tutorial-bubble points-up push-banner-bubble" aria-hidden="true">{gettext(
            "This can always be\nturned off and on\nin user settings"
          )}</span>
        </span>
        <button type="button" class="btn btn-sm btn-ghost push-banner-not-now">
          {gettext("Dismiss")}
        </button>
      </div>
    </section>
    """
  end

  @doc """
  The page title: "Page · Server name", or the server name alone.
  """
  attr :page_title, :string, default: nil

  def page_title(assigns) do
    assigns = assign(assigns, :server_name, server_name())

    ~H"""
    <.live_title
      default={@server_name}
      suffix={@page_title && " · " <> @server_name}
      phx-no-format
    >{@page_title}</.live_title>
    """
  end

  @doc """
  Renders the admin panel (AD-02): the app layout with the admin sections.

  ## Examples

      <Layouts.admin flash={@flash} current_scope={@current_scope} section={:settings}>
        <h1>Settings</h1>
      </Layouts.admin>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true

  attr :section, :atom,
    required: true,
    values: [
      :settings,
      :email,
      :users,
      :invites,
      :roles,
      :categories,
      :tags,
      :permissions,
      :stylesheet,
      :info_boxes
    ]

  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} width={:wide}>
      <nav aria-label={gettext("Admin")} class="tabs tabs-border mb-6 overflow-x-auto">
        <.link
          navigate={~p"/admin"}
          class={["tab", @section == :settings && "tab-active"]}
          aria-current={@section == :settings && "page"}
        >
          {gettext("Settings")}
        </.link>
        <.link
          navigate={~p"/admin/info-boxes"}
          class={["tab", @section == :info_boxes && "tab-active"]}
          aria-current={@section == :info_boxes && "page"}
        >
          {gettext("Info boxes")}
        </.link>
        <.link
          navigate={~p"/admin/email"}
          class={["tab", @section == :email && "tab-active"]}
          aria-current={@section == :email && "page"}
        >
          {gettext("Email")}
        </.link>
        <.link
          navigate={~p"/admin/users"}
          class={["tab", @section == :users && "tab-active"]}
          aria-current={@section == :users && "page"}
        >
          {gettext("Users")}
        </.link>
        <.link
          navigate={~p"/admin/categories"}
          class={["tab", @section == :categories && "tab-active"]}
          aria-current={@section == :categories && "page"}
        >
          {gettext("Categories")}
        </.link>
        <.link
          navigate={~p"/admin/tags"}
          class={["tab", @section == :tags && "tab-active"]}
          aria-current={@section == :tags && "page"}
        >
          {gettext("Tags")}
        </.link>
        <.link
          navigate={~p"/admin/permissions"}
          class={["tab", @section == :permissions && "tab-active"]}
          aria-current={@section == :permissions && "page"}
        >
          {gettext("Permissions")}
        </.link>
        <.link
          navigate={~p"/admin/invites"}
          class={["tab", @section == :invites && "tab-active"]}
          aria-current={@section == :invites && "page"}
        >
          {gettext("Invites")}
        </.link>
        <.link
          navigate={~p"/admin/roles"}
          class={["tab", @section == :roles && "tab-active"]}
          aria-current={@section == :roles && "page"}
        >
          {gettext("Roles")}
        </.link>
        <.link
          navigate={~p"/admin/stylesheet"}
          class={["tab", @section == :stylesheet && "tab-active"]}
          aria-current={@section == :stylesheet && "page"}
        >
          {gettext("Stylesheet")}
        </.link>
      </nav>
      <%!-- A role colour changed here shows at once, before the next page load. --%>
      <div id="admin-content" phx-hook="RoleColours">
        {render_slot(@inner_block)}
      </div>
    </Layouts.app>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Chooses the tutorial bubbles (steward decisions, 2026-10-25, 2026-10-26): All (the
  composer's, the timer line's, the sidebar's, the push banner's), Simple (the composer's
  "Enter to send" and "Sent!" only) or Off. Like the theme, theme.js applies the choice
  before the page is drawn (`data-bubbles="simple"` or `"off"` on `<html>`) and the browser
  remembers it; the stylesheet highlights the current one. Hidden without JavaScript, which the bubbles need.
  """
  attr :labelled_by, :string, required: true

  def bubbles_toggle(assigns) do
    ~H"""
    <div role="group" aria-labelledby={@labelled_by} class="theme-toggle bubbles-toggle">
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-bubbles")}
        data-choice="on"
        aria-label={gettext("Show all tutorial bubbles")}
      >
        {gettext("All")}
      </button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-bubbles")}
        data-choice="simple"
        aria-label={gettext("Show only the Enter to send and Sent! bubbles")}
      >
        {gettext("Simple")}
      </button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-bubbles")}
        data-choice="off"
        aria-label={gettext("Turn tutorial bubbles off")}
      >
        {gettext("Off")}
      </button>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  attr :class, :any, default: nil

  def theme_toggle(assigns) do
    ~H"""
    <div role="group" aria-label={gettext("Theme")} class={["theme-toggle", @class]}>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label={gettext("Use the system's theme")}
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label={gettext("Use the light theme")}
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>
      <button
        type="button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label={gettext("Use the dark theme")}
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CardComponents do
  @moduledoc """
  The cards inline links open in a topic (TP-10), from `IdejoWeb.InlineCards.load/4`: a
  preview, a link to open what it names, and an action where there is one. Each heading is
  `#inline-card-name`, which names the dialog.
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext
  use IdejoWeb, :verified_routes

  import IdejoWeb.CoreComponents, only: [icon: 1]

  alias IdejoWeb.Admin
  alias IdejoWeb.TopicComponents
  alias IdejoWeb.UserComponents

  attr :card, :map, required: true

  def inline_card(%{card: %{kind: :user}} = assigns) do
    ~H"""
    <UserComponents.user_card card={@card.card} id="inline-card" />
    <.open_link path={@card.path} label={gettext("Open profile")} />
    """
  end

  def inline_card(%{card: %{kind: :role}} = assigns) do
    ~H"""
    <h2 id="inline-card-name" class="inline-card-title">
      <span class="inline-card-sign" aria-hidden="true">+</span><Admin.role_label role={@card.role} />
    </h2>
    <p class="inline-card-meta">{ngettext("1 member", "%{count} members", @card.count)}</p>
    <ul :if={@card.members != []} class="inline-card-list" aria-label={gettext("Members")}>
      <li :for={user <- @card.members} class="flex items-center gap-2">
        <UserComponents.avatar user={user} size={:small} />
        {user.display_name}
      </li>
    </ul>
    <.open_link path={@card.path} label={gettext("See all members")} />
    """
  end

  def inline_card(%{card: %{kind: :topic}} = assigns) do
    ~H"""
    <p class="inline-card-meta">
      <TopicComponents.category_mark category={@card.topic.category} />
      {@card.topic.category.name}
    </p>
    <h2 id="inline-card-name" class="inline-card-title">{@card.topic.title}</h2>
    <p class="inline-card-meta">
      {gettext("Started by %{name}", name: @card.topic.author.display_name)} · {ngettext(
        "1 message",
        "%{count} messages",
        @card.topic.message_count
      )} · <TopicComponents.time_ago at={@card.topic.last_activity_at} />
    </p>
    <TopicComponents.tag_list tags={@card.topic.tags} />
    <p :if={@card.excerpt} class="inline-card-excerpt">{@card.excerpt}</p>
    <div class="inline-card-actions">
      <.open_link path={@card.path} label={gettext("Open topic")} />
      <button
        :if={@card.following? == false}
        type="button"
        class="btn btn-sm"
        phx-click="card_follow"
        phx-value-id={@card.topic.id}
      >
        {gettext("Follow")}
      </button>
      <button
        :if={@card.following?}
        type="button"
        class="btn btn-sm"
        phx-click="card_unfollow"
        phx-value-id={@card.topic.id}
      >
        {gettext("Unfollow")}
      </button>
    </div>
    """
  end

  def inline_card(%{card: %{kind: :category}} = assigns) do
    ~H"""
    <h2 id="inline-card-name" class="inline-card-title">
      <TopicComponents.category_mark category={@card.category} />
      {@card.category.name}
    </h2>
    <p :if={@card.category.description != ""} class="inline-card-excerpt">
      {@card.category.description}
    </p>
    <p class="inline-card-meta">{ngettext("1 topic", "%{count} topics", @card.count)}</p>
    <.topic_links topics={@card.topics} label={gettext("Latest topics")} />
    <div class="inline-card-actions">
      <.open_link path={@card.path} label={gettext("Open category")} />
      <a :if={@card.can_start?} href={~p"/c/#{@card.category.slug}/new"} class="btn btn-sm">
        <.icon name="hero-plus" class="size-4" />{gettext("New topic")}
      </a>
    </div>
    """
  end

  def inline_card(%{card: %{kind: :tag}} = assigns) do
    ~H"""
    <h2 id="inline-card-name" class="inline-card-title">
      <span class="inline-card-sign" aria-hidden="true">$</span>{@card.tag.name}
    </h2>
    <p class="inline-card-meta">
      {if @card.tag.category,
        do: gettext("A tag of %{category}", category: @card.tag.category.name),
        else: gettext("A tag for every category")}
    </p>
    <.topic_links topics={@card.topics} label={gettext("Latest topics")} />
    <p :if={@card.topics == []} class="inline-card-meta">{gettext("No topics carry it yet.")}</p>
    <.open_link path={@card.path} label={gettext("Filter by tag")} />
    """
  end

  attr :topics, :list, required: true
  attr :label, :string, required: true

  defp topic_links(assigns) do
    ~H"""
    <ul :if={@topics != []} class="inline-card-list" aria-label={@label}>
      <li :for={topic <- @topics}>
        <a href={~p"/t/#{topic.id}/#{topic.slug}"} class="link link-hover">{topic.title}</a>
      </li>
    </ul>
    """
  end

  attr :path, :string, required: true
  attr :label, :string, required: true

  defp open_link(assigns) do
    ~H"""
    <a href={@path} class="btn btn-sm btn-primary inline-card-open">
      {@label}<.icon name="hero-arrow-right-micro" class="size-4" />
    </a>
    """
  end
end

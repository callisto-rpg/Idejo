# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use IdejoWeb, :html

  embed_templates "page_html/*"

  @doc """
  The heading of a section of categories (RP-03): "Categories" when there is only one, else
  the group's name, or "Other" for the ungrouped ones.
  """
  def section_title(_group, 1), do: gettext("Categories")
  def section_title(nil, _count), do: gettext("Other")
  def section_title(group, _count), do: group.name

  @doc """
  An info box on the home page (steward decision, 2026-10-25): a card like a category's,
  without its link, its title and icon only while `show_head`.
  """
  attr :box, :map, required: true

  def info_box(assigns) do
    ~H"""
    <li id={"info-box-#{@box.id}"} class={["category-card info-box", "info-box-#{@box.id}"]}>
      <div :if={@box.show_head} class="category-card-head">
        <TopicComponents.category_mark category={info_box_mark(@box)} size={:large} />
        <h3>{@box.title}</h3>
      </div>
      <div :if={String.trim(@box.body_html) != ""} class="info-box-body">
        <MessageComponents.body html={@box.body_html} />
      </div>
    </li>
    """
  end

  @doc "An info box's mark: drawn like a category's, from its title, icon and colour."
  def info_box_mark(box), do: %{id: box.id, name: box.title, icon: box.icon, colour: box.colour}
end

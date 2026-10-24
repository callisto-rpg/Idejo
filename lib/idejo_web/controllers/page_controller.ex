# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PageController do
  use IdejoWeb, :controller

  alias Idejo.Forum

  @doc """
  The home page: the categories the visitor or user may view (AC-05), in their order, with
  their topic count and last activity, then the most recently active topics. Visitors who
  are not signed in first see a card offering to sign in (steward decision, 2026-10-24).
  """
  def home(conn, params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user
    categories = Forum.list_category_summaries(user)
    active_topics = Forum.list_active_topics(user)
    # Compact or expanded topic cards (steward decision, 2026-10-23).
    {conn, view} = IdejoWeb.TopicView.choose(conn, params)

    render(conn, :home,
      categories: categories,
      sections: Forum.sections(categories, Forum.list_groups()),
      active_topics: active_topics,
      view: view,
      previews: IdejoWeb.TopicView.previews(view, active_topics),
      # Visitors are told what signing in gives, until they continue without it.
      guest_notice?:
        is_nil(user) and !get_session(conn, IdejoWeb.GuestNoticeController.session_key()),
      canonical_url: url(~p"/")
    )
  end
end

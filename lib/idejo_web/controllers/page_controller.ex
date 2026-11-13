# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PageController do
  use IdejoWeb, :controller

  alias Idejo.Forum
  alias Idejo.Reading
  alias Idejo.Settings.InfoBoxes

  @doc """
  The home page: the categories the visitor or user may view (AC-05), in their order, with
  their topic count and last activity, the info boxes first among them (steward decision,
  2026-10-25), then the most recently active topics. Visitors who are not signed in first
  see a card offering to sign in (steward decision, 2026-10-24).
  """
  # Inbox mode (steward request, 2026-11-10): the home page is the Forums tab.
  def home(conn, params) do
    if Idejo.Inbox.on?(),
      do: IdejoWeb.InboxController.forums(conn, params),
      else: forum_home(conn, params)
  end

  defp forum_home(conn, params) do
    user = conn.assigns.current_scope && conn.assigns.current_scope.user
    categories = Forum.list_category_summaries(user)
    active_topics = user |> Forum.list_active_topics() |> Reading.put_inactive()
    # Compact or expanded topic cards (steward decision, 2026-10-23).
    {conn, view} = IdejoWeb.TopicView.choose(conn, params)
    info_boxes = InfoBoxes.list()
    {before_boxes, sections} = sections(categories, info_boxes)

    render(conn, :home,
      categories: categories,
      sections: sections,
      before_boxes: before_boxes,
      info_boxes: info_boxes,
      active_topics: active_topics,
      view: view,
      previews: IdejoWeb.TopicView.previews(view, active_topics),
      # Visitors are told what signing in gives, until they continue without it.
      guest_notice?:
        is_nil(user) and !get_session(conn, IdejoWeb.GuestNoticeController.session_key()),
      canonical_url: url(~p"/")
    )
  end

  # The info boxes before the categories, and each section as `{group, summaries, boxes
  # first, boxes last}` (steward request, 2026-11-13): a box goes in its group's section, or
  # "Other" (no group), at the start or the end; in the first one when that section is not
  # shown, so a box placed in a section always shows. With no category there is still one
  # section for them.
  defp sections(categories, info_boxes) do
    {before, placed} = Enum.split_with(info_boxes, &(&1.placement == "before"))

    sections =
      case Forum.sections(categories, Forum.list_groups()) do
        [] when placed != [] -> [{nil, []}]
        sections -> sections
      end

    by_index = Enum.group_by(placed, &section_index(&1, sections))

    {before,
     for {{group, summaries}, index} <- Enum.with_index(sections) do
       {last, first} = by_index |> Map.get(index, []) |> Enum.split_with(& &1.at_end)
       {group, summaries, first, last}
     end}
  end

  defp section_index(%{placement: "group", group_id: id}, sections) when is_binary(id),
    do: Enum.find_index(sections, &match?({%{id: ^id}, _}, &1)) || 0

  defp section_index(%{placement: "other"}, sections),
    do: Enum.find_index(sections, &match?({nil, _}, &1)) || 0

  defp section_index(_box, _sections), do: 0
end

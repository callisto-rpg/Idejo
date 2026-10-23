# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SidebarHTML do
  @moduledoc """
  The sidebar alone, for `IdejoWeb.SidebarController`: `IdejoWeb.Layouts.sidebar/1`, with no
  page around it, and the header's Unread link with its count (`Layouts.unread_link/1`).
  """
  use IdejoWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.sidebar user={@user} current={@current} />
    <Layouts.unread_link user={@user} />
    """
  end
end

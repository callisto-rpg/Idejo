# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SidebarHTML do
  @moduledoc """
  The sidebar alone, for `IdejoWeb.SidebarController`: `IdejoWeb.Layouts.sidebar/1`, with no
  page around it.
  """
  use IdejoWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.sidebar user={@user} current={@current} />
    """
  end
end

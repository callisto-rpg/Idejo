# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SidebarSwipeTest do
  use ExUnit.Case, async: true

  # The gestures themselves were checked in a browser (no JavaScript test runner here); this
  # keeps their guards in place.
  test "on narrow touch screens, swipes open and close the sidebar, with guards" do
    js = File.read!("assets/js/sidebar.js")
    assert js =~ "export function swipe(x0, y0, x1, y1, ms)"
    assert js =~ ~s(document.addEventListener("touchstart")
    assert js =~ ~s(document.addEventListener("touchend")
    assert js =~ "{passive: true}"
    # Wide screens keep the button only; edges and sideways-scrolling places are left alone.
    assert js =~ "if (wide.matches"
    assert js =~ "x0 < EDGE"
    assert js =~ ~s(const NO_SWIPE = "pre, table, input, textarea)
  end
end

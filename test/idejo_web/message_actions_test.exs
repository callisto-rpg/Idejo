# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# A message's actions (steward decision, 2026-10-25): no requirement ID.
defmodule IdejoWeb.MessageActionsTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum

  test "actions show on hover on screens that point, and as a pill when tapped on touch screens",
       %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Forum.create_topic(user_fixture(), general, %{"title" => "T", "body" => "Hi"})

    {:ok, lv, _html} =
      live_isolated(log_in_user(conn, user_fixture()), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    # The tapped state survives patches.
    assert render(lv) =~
             ~s(phx-mounted="[[&quot;ignore_attrs&quot;,{&quot;attrs&quot;:[&quot;data-acting&quot;]}]]")

    css = File.read!("assets/css/app.css")
    assert css =~ ~r/@media \(hover: hover\) \{\s*\.message \.message-actions \{ opacity: 0; \}/
    # Touch screens: hidden, not removed (screen readers reach them), only with scripts.
    # (Unless "Show message controls on mobile" is on: then in place.)
    assert css =~
             ~r/\[data-js\] #message-window:not\(\[data-controls-mobile\]\) \.message \.message-actions \{\s*position: absolute;/

    assert css =~
             "[data-js] #message-window:not([data-controls-mobile]) .message[data-acting] .message-actions,"

    js = File.read!("assets/js/message_actions.js")
    assert js =~ ~s|const touch = matchMedia("(hover: none)")|
    assert js =~ ~s|message.setAttribute("data-acting", "")|
    assert js =~ "SCROLL_CLOSES_PX"
    assert File.read!("assets/js/app.js") =~ ~s(import "./message_actions")
  end
end

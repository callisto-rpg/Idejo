# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CategoryColoursTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Forum.CategoryIcons

  @tag req: "RP-03"
  test "RP-03 pages colour each category's elements, through the CSP nonce, never style attributes" do
    admin = user_with_role_fixture(:administrator)
    {:ok, garden} = Forum.create_category(admin, %{"name" => "Garden", "colour" => "#0fa05c"})
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, team} = Forum.create_category(admin, %{"name" => "Team room"})
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), team, :view, :deny)
    {:ok, _} = Forum.create_topic(user_fixture(), garden, %{"title" => "Roses", "body" => "Hi"})

    conn = get(build_conn(), ~p"/")
    html = html_response(conn, 200)
    [policy] = get_resp_header(conn, "content-security-policy")
    [_, nonce] = Regex.run(~r/style-src 'self' 'nonce-([^']+)'/, policy)

    assert html =~ ~r/<style[^>]* nonce="#{nonce}">/
    assert html =~ ".cat-#{garden.id}{--cat:#0fa05c}"
    assert html =~ ".cat-#{general.id}{--cat:#{CategoryIcons.tint(general.id)}}"
    # A category the visitor may not view gives nothing away (AC-05).
    refute html =~ team.id
    refute html =~ ~r/\sstyle="/

    assert html =~ ~s(class="category-card cat-#{garden.id}")
    assert html =~ ~s(class="topic-row cat-#{garden.id}")
  end
end

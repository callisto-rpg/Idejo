# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SE04PublicPagesTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, team} = Forum.create_category(admin, %{"name" => "Team room"})
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), team, :view, :deny)

    member = user_fixture()
    {:ok, open} = Forum.create_topic(member, general, %{"title" => "Open talk", "body" => "Hi"})
    {:ok, closed} = Forum.create_topic(member, team, %{"title" => "Team only", "body" => "Hi"})

    %{admin: admin, general: general, team: team, open: open, closed: closed}
  end

  defp canonical(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(~s(link[rel="canonical"]))
    |> LazyHTML.attribute("href")
  end

  @tag req: "SE-04"
  test "SE-04 public pages are server-rendered at clean URLs", %{conn: conn, open: open} do
    for path <- [~p"/", ~p"/c/general", ~p"/t/#{open.id}/open-talk"] do
      html = conn |> get(path) |> html_response(200)
      refute html =~ "data-phx-main"
    end
  end

  @tag req: "SE-04"
  test "SE-04 public pages name their canonical address", %{conn: conn, open: open} do
    base = IdejoWeb.Endpoint.url()

    assert canonical(conn |> get(~p"/") |> html_response(200)) == [base <> "/"]
    assert canonical(conn |> get(~p"/c/general") |> html_response(200)) == [base <> "/c/general"]

    assert canonical(conn |> get(~p"/c/general?page=2") |> html_response(200)) ==
             [base <> "/c/general?page=2"]

    topic_html = conn |> get(~p"/t/#{open.id}/open-talk?reply_to=x") |> html_response(200)
    assert canonical(topic_html) == [base <> "/t/#{open.id}/open-talk"]
  end

  @tag req: "SE-04"
  test "SE-04 the sitemap lists public pages only, at their canonical addresses", %{
    conn: conn,
    open: open,
    closed: closed
  } do
    conn = get(conn, ~p"/sitemap.xml")
    assert response_content_type(conn, :xml) =~ "application/xml"
    xml = response(conn, 200)
    base = IdejoWeb.Endpoint.url()

    assert xml =~ ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
    assert xml =~ "<loc>#{base}/</loc>"
    assert xml =~ "<loc>#{base}/c/general</loc>"
    assert xml =~ "<loc>#{base}/t/#{open.id}/open-talk</loc><lastmod>"
    refute xml =~ "team-room"
    refute xml =~ closed.id
  end

  @tag req: "SE-04"
  test "SE-04 the Archive stays out of the sitemap until shown to visitors", %{
    conn: conn,
    admin: admin,
    general: general,
    open: open
  } do
    {:ok, _} = Forum.delete_category(admin, general, topics: :archive)
    refute conn |> get(~p"/sitemap.xml") |> response(200) =~ open.id

    {:ok, archive} = Forum.archive_category(admin)
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), archive, :view, :allow)
    assert conn |> get(~p"/sitemap.xml") |> response(200) =~ open.id
  end

  @tag req: "SE-04"
  test "SE-04 robots.txt names the sitemap", %{conn: conn} do
    body = conn |> get(~p"/robots.txt") |> response(200)
    assert body =~ "User-agent: *"
    assert body =~ "Sitemap: #{IdejoWeb.Endpoint.url()}/sitemap.xml"
  end
end

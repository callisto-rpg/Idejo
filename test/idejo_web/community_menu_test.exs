# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.CommunityMenuTest do
  @moduledoc """
  The community menu (steward decision, 2026-11-06): with IDEJO_COMMUNITY_URL or
  IDEJO_COMMUNITY_DIRECTORY_URL set, the forum's icon opens a menu of the member's other
  communities and "Find more forums"; unset, it stays a link home. And on narrow screens a
  visible "Show the sidebar" button.
  """
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Accounts.UserIdentity
  alias Idejo.{Community, Repo}
  alias IdejoWeb.Accessibility

  @issuer "https://id.example.test"
  @directory "https://forums.example.test/"

  setup do
    community = Application.get_env(:idejo, :community)
    oidc = Application.get_env(:idejo, :oidc)

    on_exit(fn ->
      Application.put_env(:idejo, :community, community)

      if oidc,
        do: Application.put_env(:idejo, :oidc, oidc),
        else: Application.delete_env(:idejo, :oidc)
    end)

    :ok
  end

  defp community_on do
    Application.put_env(:idejo, :community,
      url: "http://hub.example.test/internal/community",
      directory_url: @directory
    )

    Application.put_env(:idejo, :oidc,
      issuer: @issuer,
      client_id: "forum-client",
      client_secret: "forum-secret",
      label: "Example ID"
    )
  end

  defp linked_member(subject) do
    user = user_fixture()
    Repo.insert!(UserIdentity.changeset(%{user_id: user.id, issuer: @issuer, subject: subject}))
    user
  end

  test "standalone: the forum's icon stays a link home, and nothing is asked", %{conn: conn} do
    Application.put_env(:idejo, :community, url: nil, directory_url: nil)
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(<a href="/" class="brand" id="brand">)
    refute html =~ "community-menu"
    assert Community.communities(user_fixture()) == []
  end

  test "the server asks with its client's credentials and the member's subject" do
    community_on()
    member = linked_member("ada-1")

    Req.Test.stub(Community, fn conn ->
      assert conn.query_string == "subject=ada-1"

      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("forum-client:forum-secret")
             ]

      Req.Test.json(conn, %{
        "communities" => [
          %{"name" => "Chess club", "url" => "https://chess.example.test/"},
          %{"name" => "Bad", "url" => "javascript:alert(1)"}
        ]
      })
    end)

    assert Community.communities(member) == [
             %{name: "Chess club", url: "https://chess.example.test/"}
           ]

    # Members not linked to the provider have no subject: nothing is asked.
    assert Community.communities(user_fixture()) == []
  end

  test "a slow or failed answer gives an empty list, never an error" do
    community_on()
    member = linked_member("ada-2")
    Req.Test.stub(Community, &Plug.Conn.send_resp(&1, 503, "down"))
    assert Community.communities(member) == []
    Req.Test.stub(Community, &Req.Test.transport_error(&1, :timeout))
    assert Community.communities(linked_member("ada-3")) == []
  end

  test "with the community set, the icon opens a menu: this forum, the member's list, the directory",
       %{conn: conn} do
    community_on()
    member = linked_member("ada-4")

    Req.Test.stub(Community, fn conn ->
      Req.Test.json(conn, %{
        "communities" => [%{"name" => "Chess club", "url" => "https://chess.example.test/"}]
      })
    end)

    html = conn |> log_in_user(member) |> get(~p"/") |> html_response(200)
    doc = LazyHTML.from_document(html)

    assert doc
           |> LazyHTML.query("details#community-menu > summary#brand > img.brand-mark")
           |> Enum.count() == 1

    assert doc |> LazyHTML.query(~s(#community-home[href="/"])) |> Enum.count() == 1

    assert doc
           |> LazyHTML.query(~s(#community-list[data-src="/community"][hidden]))
           |> Enum.count() == 1

    assert doc
           |> LazyHTML.query(~s(#community-directory[href="#{@directory}"]))
           |> LazyHTML.text() =~ "Find more forums"

    assert Accessibility.audit(html) == []

    # The list the script fills.
    json = conn |> log_in_user(member) |> get(~p"/community") |> json_response(200)

    # Asked as a script asks for JSON, too (it got 406 once: steward report, 2026-11-06).
    assert conn
           |> recycle()
           |> log_in_user(member)
           |> put_req_header("accept", "application/json")
           |> get(~p"/community")
           |> json_response(200) == json

    assert json == %{
             "communities" => [%{"name" => "Chess club", "url" => "https://chess.example.test/"}]
           }

    # Visitors: the menu, without a personal list.
    visitor = build_conn() |> get(~p"/") |> html_response(200)
    assert visitor =~ ~s(id="community-directory")
    refute visitor =~ ~s(id="community-list")
    assert build_conn() |> get(~p"/community") |> json_response(200) == %{"communities" => []}
  end

  test "standalone: Show the sidebar stays at the top of the page", %{conn: conn} do
    Application.put_env(:idejo, :community, url: nil, directory_url: nil)
    html = conn |> get(~p"/") |> html_response(200)
    doc = LazyHTML.from_document(html)
    button = LazyHTML.query(doc, ~s(.app-column > button#sidebar-show[aria-controls="sidebar"]))
    assert LazyHTML.text(button) =~ "Show the sidebar"
  end

  test "with the community menu, Show the sidebar is its first item, above the forums",
       %{conn: conn} do
    community_on()
    html = conn |> get(~p"/") |> html_response(200)
    doc = LazyHTML.from_document(html)
    assert doc |> LazyHTML.query("#sidebar-show") |> Enum.count() == 1
    first = LazyHTML.query(doc, ".community-panel > :first-child")
    assert LazyHTML.attribute(first, "id") == ["sidebar-show"]
    assert LazyHTML.text(first) =~ "Show the sidebar"
  end

  test "a member not linked to the provider is offered to connect it, to see more forums",
       %{conn: conn} do
    community_on()
    Req.Test.stub(Community, &Req.Test.json(&1, %{"communities" => []}))

    unlinked = conn |> log_in_user(user_fixture()) |> get(~p"/") |> html_response(200)

    link =
      unlinked |> LazyHTML.from_document() |> LazyHTML.query("#community-menu #community-connect")

    assert LazyHTML.attribute(link, "href") == ["/users/settings?tab=account#oidc-section"]
    assert LazyHTML.text(link) =~ "Connect Example ID to view more forums"
    assert Accessibility.audit(unlinked) == []

    linked =
      build_conn() |> log_in_user(linked_member("ada-9")) |> get(~p"/") |> html_response(200)

    refute linked =~ "community-connect"
    refute build_conn() |> get(~p"/") |> html_response(200) =~ "community-connect"
  end

  test "the menu may show the other forums' logos: their shared domain, images only", %{
    conn: conn
  } do
    community_on()
    [csp] = conn |> get(~p"/") |> get_resp_header("content-security-policy")
    [img] = csp |> String.split("; ") |> Enum.filter(&String.starts_with?(&1, "img-src"))
    assert img =~ " https://*.example.test"
    refute csp =~ ~r/(connect|script|default)-src[^;]*\*\.example\.test/

    # Standalone, or a directory one label under a top-level domain: nothing added.
    for directory <- [nil, "https://forums.org/"] do
      Application.put_env(:idejo, :community, url: nil, directory_url: directory)
      [csp] = build_conn() |> get(~p"/") |> get_resp_header("content-security-policy")
      refute csp =~ "https://*.", inspect(directory)
    end
  end

  test "the dropdown arrow shows only while no breadcrumb follows the forum's name", %{
    conn: conn
  } do
    community_on()
    admin = user_with_role_fixture(:administrator)
    {:ok, category} = Idejo.Forum.create_category(admin, %{"name" => "Garden"})

    {:ok, topic} =
      Idejo.Forum.create_topic(admin, category, %{"title" => "Plans", "body" => "Soon."})

    home = conn |> get(~p"/") |> html_response(200)
    assert home =~ "community-chevron"
    refute home =~ ~s(id="breadcrumb")

    for path <- [~p"/c/#{category.slug}", ~p"/t/#{topic.id}/#{topic.slug}"] do
      page = build_conn() |> get(path) |> html_response(200)
      assert page =~ ~s(id="breadcrumb"), path
      assert page =~ ~s(id="community-menu"), path
      refute page =~ "community-chevron", path
    end
  end
end

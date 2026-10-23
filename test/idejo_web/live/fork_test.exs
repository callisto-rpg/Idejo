# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ForkTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Repo

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})
    ada = user_fixture(%{display_name: "Ada"})

    {:ok, topic} =
      Forum.create_topic(ada, general, %{"title" => "Tonight", "body" => "Who brings **bread**?"})

    [source] = Forum.list_messages(topic)
    member = user_fixture(%{display_name: "Bo"})

    %{
      conn: log_in_user(conn, member),
      admin: admin,
      general: general,
      help: help,
      member: member,
      topic: topic,
      source: source
    }
  end

  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  defp deny(admin, role, category, right),
    do:
      {:ok, _} = Access.set_permission(admin, Access.built_in_role!(role), category, right, :deny)

  @tag req: "TP-09"
  test "TP-09 a member starts a topic from someone else's message; both link to each other", %{
    conn: conn,
    help: help,
    topic: topic,
    source: source
  } do
    {:ok, source_view, _html} = watch(conn, topic)
    {:ok, visitor_view, _html} = watch(build_conn(), topic)

    assert has_element?(
             source_view,
             ~s(#message-#{source.id}-fork[href="/m/#{source.id}/new-topic"]),
             "New topic from this"
           )

    {:ok, lv, html} = live(conn, ~p"/m/#{source.id}/new-topic")
    assert html =~ "From Ada in “Tonight”"
    assert html =~ "Who brings bread?"
    assert has_element?(lv, ~s(#forked-from a[href="/m/#{source.id}"]))
    # The source's category comes first; the user may pick another they can start in.
    assert has_element?(lv, "#topic_category_id option[selected]", "General")
    assert has_element?(lv, "#topic_category_id option", "Help")

    {:ok, conn} =
      lv
      |> form("#new-topic-form",
        topic: %{category_id: help.id, title: "Bread recipes", body: "Sourdough?"}
      )
      |> render_submit()
      |> follow_redirect(conn)

    fork = Repo.get_by!(Topic, title: "Bread recipes")
    assert fork.category_id == help.id
    assert fork.forked_from_message_id == source.id

    page = html_response(conn, 200)
    doc = LazyHTML.from_document(page)
    assert doc |> LazyHTML.query(~s(#forked-from a[href="/m/#{source.id}"])) |> Enum.count() == 1
    assert page =~ "Continued from Ada in “Tonight”"

    # The source message gets a discreet "continued in" link, live, for everyone who may see it.
    for view <- [source_view, visitor_view] do
      assert has_element?(
               view,
               ~s(#message-#{source.id}-forks a[href="/t/#{fork.id}/#{fork.slug}"][aria-label="Continue topic: Bread recipes"]),
               "Continue topic"
             )
    end

    assert %Activity{payload: %{"forkedFrom" => uri}} =
             Repo.get_by!(Activity, object_uri: fork.uri)

    assert uri == source.uri
  end

  @tag req: "TP-09"
  test "TP-09 forking needs the start right in the target and view of the source", %{
    admin: admin,
    general: general,
    help: help,
    member: member,
    source: source
  } do
    deny(admin, :member, help, :start)
    assert Enum.map(Forum.list_startable_categories(member), & &1.name) == ["General"]

    assert Forum.create_topic(member, help, %{"title" => "X", "body" => "Y"}, forked_from: source) ==
             {:error, :forbidden}

    deny(admin, :member, general, :view)
    deny(admin, :guest, general, :view)
    {:ok, open} = Forum.create_category(admin, %{"name" => "Open"})

    assert Forum.create_topic(member, open, %{"title" => "X", "body" => "Y"}, forked_from: source) ==
             {:error, :forbidden}
  end

  @tag req: "TP-09"
  test "TP-09 links never show a topic the viewer may not view", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic,
    source: source
  } do
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff"})

    {:ok, fork} =
      Forum.create_topic(admin, staff, %{"title" => "Staff talk", "body" => "Hm"},
        forked_from: source
      )

    deny(admin, :member, staff, :view)
    deny(admin, :guest, staff, :view)

    {:ok, view, _html} = watch(conn, topic)
    refute has_element?(view, "#message-#{source.id}-forks")
    refute render(view) =~ "Staff talk"

    # And the other way: a public fork of a message now hidden shows no link back.
    {:ok, public} =
      Forum.create_topic(
        admin,
        Forum.get_category_by_slug("help"),
        %{
          "title" => "Public",
          "body" => "Hi"
        },
        forked_from: source
      )

    deny(admin, :member, general, :view)
    deny(admin, :guest, general, :view)
    refute conn |> get(~p"/t/#{public.id}/#{public.slug}") |> html_response(200) =~ "forked-from"
    assert fork.forked_from_message_id == source.id
  end

  @tag req: "TP-09"
  test "TP-09 visitors and users who cannot start topics get no fork link", %{
    conn: conn,
    admin: admin,
    general: general,
    help: help,
    topic: topic,
    source: source
  } do
    {:ok, visitor, _html} = watch(build_conn(), topic)
    refute has_element?(visitor, "#message-#{source.id}-fork")

    deny(admin, :member, general, :start)
    deny(admin, :member, help, :start)

    {:ok, view, _html} = watch(conn, topic)
    refute has_element?(view, "#message-#{source.id}-fork")

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/m/#{source.id}/new-topic")
    assert to == ~p"/m/#{source.id}"
  end
end

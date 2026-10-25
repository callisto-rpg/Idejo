# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.FollowTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Reading

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()

    {:ok, topic} =
      Forum.create_topic(starter, general, %{"title" => "Picnic", "body" => "Saturday?"})

    member = user_fixture()

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{
      conn: log_in_user(conn, member),
      admin: admin,
      general: general,
      starter: starter,
      member: member,
      topic: topic
    }
  end

  defp topic_page(conn, topic),
    do: conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)

  @tag req: "TP-13"
  test "TP-13 a member follows and unfollows a topic from its page, without JavaScript", %{
    conn: conn,
    member: member,
    topic: topic
  } do
    page = topic_page(conn, topic)
    assert page =~ ~s(id="follow-form")
    assert page =~ ~s(action="/t/#{topic.id}/follow")
    refute Reading.following?(member, topic)

    conn = post(conn, ~p"/t/#{topic.id}/follow")
    assert redirected_to(conn) == ~p"/t/#{topic.id}/#{topic.slug}"
    assert Reading.following?(member, topic)

    page = conn |> recycle() |> topic_page(topic)
    assert page =~ "You follow this topic."

    assert page
           |> LazyHTML.from_document()
           |> LazyHTML.query(~s(#unfollow-form input[name="_method"][value="delete"]))
           |> Enum.count() == 1

    conn = conn |> recycle() |> delete(~p"/t/#{topic.id}/follow")
    assert redirected_to(conn) == ~p"/t/#{topic.id}/#{topic.slug}"
    refute Reading.following?(member, topic)
  end

  @tag req: "TP-13"
  test "TP-13 starting a topic or posting in it follows it", %{
    general: general,
    starter: starter,
    member: member,
    topic: topic
  } do
    assert Reading.following?(starter, topic)

    {:ok, _} = Forum.post_message(member, topic, %{"body" => "Me too"})
    assert Reading.following?(member, topic)

    live = user_fixture()
    {:ok, _} = Messages.commit(live, topic, "Hello")
    assert Reading.following?(live, topic)

    {:ok, other} = Forum.create_topic(member, general, %{"title" => "Mine", "body" => "Hi"})
    assert Reading.following?(member, other)
  end

  @tag req: "TP-13"
  test "TP-13 an unfollow is kept when the user posts again", %{
    conn: conn,
    member: member,
    topic: topic
  } do
    {:ok, _} = Forum.post_message(member, topic, %{"body" => "First"})
    delete(conn, ~p"/t/#{topic.id}/follow")
    {:ok, _} = Forum.post_message(member, topic, %{"body" => "Second"})
    refute Reading.following?(member, topic)

    :ok = Reading.follow(member, topic)
    assert Reading.following?(member, topic)
  end

  @tag req: "TP-13"
  test "TP-13 visitors see no follow button; hidden topics cannot be followed", %{
    conn: conn,
    admin: admin,
    member: member
  } do
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff"})
    {:ok, hidden} = Forum.create_topic(admin, staff, %{"title" => "Secret", "body" => "Shh"})
    refute topic_page(build_conn(), hidden) =~ "follow-form"

    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), staff, :view, :deny)
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), staff, :view, :deny)

    assert_error_sent 404, fn -> post(conn, ~p"/t/#{hidden.id}/follow") end
    refute Reading.following?(member, hidden)

    assert redirected_to(post(build_conn(), ~p"/t/#{hidden.id}/follow")) == ~p"/users/sign-in"
  end

  defp sidebar_titles(html, selector) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  @tag req: "TP-13"
  test "TP-13 the sidebar lists followed topics under their category, oldest followed first", %{
    conn: conn,
    general: general,
    member: member,
    topic: topic
  } do
    titles = for n <- 1..6, do: "Topic #{n}"

    for title <- titles,
        do: {:ok, _} = Forum.create_topic(member, general, %{"title" => title, "body" => "Hi"})

    # Following an older topic later puts it last; activity does not reorder the list.
    :ok = Reading.follow(member, topic)
    {:ok, _} = Forum.post_message(member, topic, %{"body" => "Bump"})

    html = conn |> get(~p"/c/#{general.slug}") |> html_response(200)

    assert sidebar_titles(
             html,
             "#sidebar .sidebar-nav > ul > li > .sidebar-topics > .sidebar-topic > a .sidebar-topic-name"
           ) ==
             ["Topic 1", "Topic 2", "Topic 3", "Topic 4"]

    assert sidebar_titles(
             html,
             "#sidebar details.sidebar-more .sidebar-topic > a .sidebar-topic-name"
           ) ==
             ["Topic 5", "Topic 6", "Picnic"]

    assert html =~ "3 more topics"
  end

  @tag req: "TP-13"
  test "TP-13 the sidebar's unfollow leads back to the page it came from", %{
    conn: conn,
    general: general,
    member: member,
    topic: topic
  } do
    :ok = Reading.follow(member, topic)
    html = conn |> get(~p"/c/#{general.slug}") |> html_response(200)
    assert sidebar_titles(html, "#sidebar .sidebar-topic > a .sidebar-topic-name") == ["Picnic"]

    assert html
           |> LazyHTML.from_document()
           |> LazyHTML.query(
             ~s(#sidebar form[action="/t/#{topic.id}/follow"] button[aria-label="Unfollow Picnic"])
           )
           |> Enum.count() == 1

    # Its tutorial bubble (steward decisions, 2026-10-25), at its right on hover or focus,
    # and for 3 s on touch screens; the fold button's says what a click does
    # (assets/js/sidebar.js: one fixed bubble on <body>, never clipped by the sidebar).
    doc = LazyHTML.from_document(html)

    assert doc
           |> LazyHTML.query(
             ~s(#sidebar form[action="/t/#{topic.id}/follow"] button[data-bubble="close & unfollow thread"])
           )
           |> Enum.count() == 1

    [fold] = doc |> LazyHTML.query("#sidebar .sidebar-fold") |> Enum.to_list()
    assert LazyHTML.attribute(fold, "data-bubble") == ["Hide topics with\nno new messages"]
    assert LazyHTML.attribute(fold, "data-bubble-folded") == ["Show all followed topics"]

    js = File.read!("assets/js/sidebar.js")
    assert js =~ "const PEEK_MS = 3000"
    assert js =~ ~s|floating.className = "tutorial-bubble sidebar-bubble"|
    assert js =~ "floating.style.left = `${r.right + 8}px`"
    assert File.read!("assets/css/app.css") =~ ~r/\.sidebar-bubble \{\s*position: fixed;/

    conn =
      build_conn()
      |> log_in_user(member)
      |> put_req_header("referer", "http://www.example.com/c/#{general.slug}?page=2")
      |> delete(~p"/t/#{topic.id}/follow", %{"return" => "back"})

    assert redirected_to(conn) == "/c/#{general.slug}?page=2"
    refute Reading.following?(member, topic)

    html = conn |> recycle() |> get(~p"/c/#{general.slug}") |> html_response(200)
    assert sidebar_titles(html, "#sidebar .sidebar-topic > a .sidebar-topic-name") == []

    # Another server's page, or none, leads to the topic.
    for referer <- ["http://evil.example/c/x", "http://www.example.com//evil.example"] do
      conn =
        build_conn()
        |> log_in_user(member)
        |> put_req_header("referer", referer)
        |> delete(~p"/t/#{topic.id}/follow", %{"return" => "back"})

      assert redirected_to(conn) == ~p"/t/#{topic.id}/#{topic.slug}"
    end
  end
end

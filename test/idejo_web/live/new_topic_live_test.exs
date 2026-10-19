# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.NewTopicLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture(%{display_name: "Mia Member"})
    %{conn: log_in_user(conn, member), admin: admin, general: general, member: member}
  end

  @tag req: "TP-01"
  test "TP-01 the category page offers New topic only to those who may start one", %{
    conn: conn,
    admin: admin,
    general: general
  } do
    assert conn |> get(~p"/c/general") |> html_response(200) =~ ~s(href="/c/general/new")
    refute build_conn() |> get(~p"/c/general") |> html_response(200) =~ "/c/general/new"

    {:ok, _} =
      Access.set_permission(admin, Access.built_in_role!(:member), general, :start, :deny)

    refute conn |> get(~p"/c/general") |> html_response(200) =~ "/c/general/new"
  end

  @tag req: "TP-01"
  test "TP-01 a member posts a new topic and lands on it", %{conn: conn, member: member} do
    {:ok, lv, _html} = live(conn, ~p"/c/general/new")

    {:ok, conn} =
      lv
      |> form("#new-topic-form", topic: %{title: "Hello there", body: "First **words**"})
      |> render_submit()
      |> follow_redirect(conn)

    [topic] = Idejo.Repo.all(Idejo.Forum.Topic)
    assert topic.author_id == member.id
    assert conn.request_path == "/t/#{topic.id}/hello-there"

    html = html_response(conn, 200)
    assert html =~ "Hello there"
    assert html =~ "Mia Member"
    assert html =~ "<strong>words</strong>"
    assert html =~ "Hello there · Idejo"
  end

  @tag req: "TP-01"
  test "TP-01 errors are shown and nothing is posted", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/c/general/new")

    html = lv |> form("#new-topic-form", topic: %{title: "", body: ""}) |> render_submit()
    assert html =~ "can&#39;t be blank"
    refute Idejo.Repo.exists?(Idejo.Forum.Topic)
  end

  @tag req: "TP-01"
  test "TP-01 the new-topic page needs a signed-in user with the start right", %{
    conn: conn,
    admin: admin,
    general: general
  } do
    assert redirected_to(get(build_conn(), ~p"/c/general/new")) == ~p"/users/sign-in"

    {:ok, _} =
      Access.set_permission(admin, Access.built_in_role!(:member), general, :start, :deny)

    assert {:error, {:redirect, %{to: "/c/general", flash: %{"error" => error}}}} =
             live(conn, ~p"/c/general/new")

    assert error =~ "You cannot start topics in this category."
  end
end

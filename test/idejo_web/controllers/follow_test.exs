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
end

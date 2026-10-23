# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.RoleNamesTest do
  @moduledoc """
  Role names in their role's colour, grey without one, and "Visible next to name" (steward
  decision, 2026-10-23): a role kept off the line next to its members' names in conversations.
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Audit
  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    %{admin: admin, general: general}
  end

  defp role(admin, attrs) do
    {:ok, role} = Access.create_role(admin, Map.put(attrs, "name", unique_role_name("Team")))
    role
  end

  # New roles rank just above guest; one place up puts them above member.
  defp above_member(admin, role) do
    {:ok, _} = Access.move_role(admin, role, :up)
    Idejo.Repo.reload!(role)
  end

  defp holder(admin, roles) do
    user = user_fixture()
    for role <- roles, do: {:ok, _} = Access.assign_role(admin, user, role)
    user
  end

  defp author_role(conn, general, author) do
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Chat", "body" => "Hi"})

    {:ok, lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    [message] = Forum.list_messages(topic)
    lv |> element("#message-#{message.id} .author-line") |> render()
  end

  @tag req: "RP-02"
  test "RP-02 a role is visible next to names unless the editor turns it off", %{admin: admin} do
    team = role(admin, %{})
    assert team.show_next_to_name

    {:ok, team} = Access.update_role(admin, team, %{"show_next_to_name" => "false"})
    refute team.show_next_to_name

    entry = Enum.find(Audit.list_entries(), &(&1.change == "role.update"))
    assert {entry.before["show_next_to_name"], entry.after["show_next_to_name"]} == {true, false}

    # Built-in roles take it too, member and guest included.
    changeset =
      Access.change_role(Access.built_in_role!(:member), %{"show_next_to_name" => "false"})

    assert Ecto.Changeset.get_change(changeset, :show_next_to_name) == false
  end

  @tag req: "RP-02"
  test "RP-02 the role editor's toggle saves it and the list says so", %{conn: conn, admin: admin} do
    team = role(admin, %{})
    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/roles")

    lv |> element("#role-#{team.id} button", "Edit") |> render_click()

    lv
    |> form("#edit-role-#{team.id}", edit: %{show_next_to_name: "false"})
    |> render_submit()

    refute Idejo.Repo.reload!(team).show_next_to_name
    assert lv |> element("#role-#{team.id}") |> render() =~ "not shown next to names"
  end

  @tag req: "RP-02"
  test "RP-02 conversations show the highest role visible next to the name, in its colour",
       %{conn: conn, admin: admin, general: general} do
    conn = log_in_user(conn, user_fixture())

    team = above_member(admin, role(admin, %{"colour" => "#3366ff"}))
    html = author_role(conn, general, holder(admin, [team]))
    assert html =~ ~s(class="role-name role-#{team.id} author-role")
    assert html =~ ~s(data-role-colour="#3366ff")
    refute html =~ "<svg"

    # A hidden role stays held but gives way to the next visible one: here, member, grey.
    hidden =
      above_member(admin, role(admin, %{"colour" => "#aa2255", "show_next_to_name" => "false"}))

    html = author_role(conn, general, holder(admin, [hidden]))
    refute html =~ hidden.name
    assert html =~ "Member"
    refute html =~ "data-role-colour"
  end

  @tag req: "RP-06"
  test "RP-06 the page sets each role's colour on its class; names take their name colour",
       %{conn: conn, admin: admin} do
    team = role(admin, %{"colour" => "#3366ff"})
    plain = role(admin, %{})
    user = holder(admin, [team, plain])

    html = conn |> get(~p"/u/#{user.id}") |> html_response(200)
    assert html =~ ".role-#{team.id}{--role:#3366ff}"
    refute html =~ ".role-#{plain.id}{"
    assert html =~ ~s(class="role-name role-#{plain.id}")

    {:ok, lv, _html} = live(log_in_user(build_conn(), admin), ~p"/admin/users/#{user.id}")
    assert has_element?(lv, ".name-colour.role-#{team.id}[data-role-colour='#3366ff']")
  end
end

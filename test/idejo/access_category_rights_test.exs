# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccessCategoryRightsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Access.{CategoryPermission, Role}
  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Forum.Category

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, news} = Forum.create_category(admin, %{"name" => "Announcements"})
    team = Repo.insert!(%Role{name: "Team", position: 4})

    %{admin: admin, general: general, news: news, team: team}
  end

  defp rights(user, category), do: Enum.filter(Access.rights(), &Access.can?(user, &1, category))

  defp holding(role) do
    user = user_fixture()
    :ok = Access.grant_role(user, role)
    user
  end

  defp set!(admin, role, scope, right, effect) do
    {:ok, ^effect} = Access.set_permission(admin, role, scope, right, effect)
  end

  describe "server-wide defaults" do
    @tag req: "RP-04"
    test "RP-04 visitors and unverified users view; members view, start and post", %{
      general: general
    } do
      assert rights(nil, general) == [:view]
      assert rights(unconfirmed_user_fixture(), general) == [:view]
      assert rights(user_fixture(), general) == [:view, :start, :post]
    end

    @tag req: "RP-04"
    test "RP-04 moderators also moderate and edit tags (TP-19)", %{general: general} do
      assert rights(user_with_role_fixture(:moderator), general) == [
               :view,
               :start,
               :post,
               :moderate,
               :tag
             ]
    end

    @tag req: "RP-04"
    test "RP-04 a new custom role starts with no rights of its own", %{
      team: team,
      general: general
    } do
      assert Access.permissions(:server)
             |> Map.keys()
             |> Enum.all?(fn {role_id, _} -> role_id != team.id end)

      # Its holders keep what member gives them.
      assert rights(holding(team), general) == [:view, :start, :post]
    end
  end

  describe "owner and administrator" do
    @tag req: "RP-04"
    test "RP-04 always have every right, whatever is denied", %{admin: admin, news: news} do
      for role <- Access.list_roles(),
          role.name not in ~w(owner administrator),
          right <- Access.rights() do
        Access.set_permission(admin, role, news, right, :deny)
      end

      assert rights(admin, news) == Access.rights()
      assert rights(user_with_role_fixture(:owner), news) == Access.rights()
      assert rights(nil, news) == []
    end

    @tag req: "RP-04"
    test "RP-04 take no settings, so nobody can deny them anything", %{admin: admin, news: news} do
      for name <- [:owner, :administrator],
          scope <- [news, :server],
          effect <- [:allow, :deny, :unset] do
        assert {:error, :always_all_rights} =
                 Access.set_permission(admin, Access.built_in_role!(name), scope, :view, effect)
      end
    end
  end

  describe "category settings" do
    @tag req: "RP-04"
    test "RP-04 a deny on a category overrides the role's server-wide allow there", %{
      admin: admin,
      news: news,
      general: general
    } do
      set!(admin, Access.built_in_role!(:member), news, :start, :deny)
      set!(admin, Access.built_in_role!(:member), news, :post, :deny)

      member = user_fixture()
      assert rights(member, news) == [:view]
      assert rights(member, general) == [:view, :start, :post]
    end

    @tag req: "RP-04"
    test "RP-04 a members-only category: guests denied view", %{admin: admin, general: general} do
      set!(admin, Access.built_in_role!(:guest), general, :view, :deny)

      refute Access.can?(nil, :view, general)
      refute Access.can?(unconfirmed_user_fixture(), :view, general)
      assert Access.can?(user_fixture(), :view, general)
    end

    @tag req: "RP-04"
    test "RP-04 an allow on a category gives a role a right it lacks server-wide", %{
      admin: admin,
      team: team,
      general: general,
      news: news
    } do
      set!(admin, team, general, :moderate, :allow)
      team_member = holding(team)

      assert Access.can?(team_member, :moderate, general)
      refute Access.can?(team_member, :moderate, news)
      refute Access.can?(user_fixture(), :moderate, general)
    end

    @tag req: "RP-04"
    test "RP-04 allow wins across roles (RP-06): one allowing role is enough", %{
      admin: admin,
      team: team,
      news: news
    } do
      set!(admin, Access.built_in_role!(:member), news, :post, :deny)
      set!(admin, team, news, :post, :allow)

      assert Access.can?(holding(team), :post, news)
      refute Access.can?(user_fixture(), :post, news)
    end

    @tag req: "RP-04"
    test "RP-04 unset follows the server-wide setting, also when it changes", %{
      admin: admin,
      team: team,
      general: general
    } do
      team_member = holding(team)
      refute Access.can?(team_member, :moderate, general)

      set!(admin, team, :server, :moderate, :allow)
      assert Access.can?(team_member, :moderate, general)

      set!(admin, team, general, :moderate, :deny)
      refute Access.can?(team_member, :moderate, general)

      set!(admin, team, general, :moderate, :unset)
      assert Access.can?(team_member, :moderate, general)
    end

    @tag req: "RP-04"
    test "RP-04 server-wide, a right is allowed or unset, never denied", %{
      admin: admin,
      team: team
    } do
      assert {:error, :no_server_deny} = Access.set_permission(admin, team, :server, :view, :deny)
    end
  end

  describe "where_allowed/3" do
    @tag req: "RP-04"
    test "RP-04 lists only what the visitor may view, filtered in the query", %{
      admin: admin,
      general: general,
      news: news
    } do
      set!(admin, Access.built_in_role!(:guest), news, :view, :deny)

      visible = fn user ->
        Category
        |> Access.where_allowed(user, :view)
        |> Repo.all()
        |> Enum.map(& &1.slug)
        |> Enum.sort()
      end

      assert visible.(nil) == [general.slug]
      assert visible.(user_fixture()) == Enum.sort([general.slug, news.slug])
      assert visible.(admin) == Enum.sort([general.slug, news.slug])

      # It composes with other conditions.
      query = from(c in Category, where: c.slug == ^news.slug)
      assert Repo.all(Access.where_allowed(query, nil, :view)) == []
    end
  end

  describe "set_permission/5" do
    @tag req: "RP-04"
    test "RP-04 changes are stored, listed and audited (SP-06)", %{
      admin: admin,
      team: team,
      news: news
    } do
      set!(admin, team, news, :post, :allow)
      set!(admin, team, news, :post, :deny)

      assert Access.permissions(news) == %{{team.id, :post} => :deny}

      assert [latest, first] =
               Audit.list_entries() |> Enum.filter(&(&1.change == "permission.update"))

      assert first.before == %{
               "role" => "Team",
               "category" => news.slug,
               "right" => "post",
               "effect" => "unset"
             }

      assert first.after["effect"] == "allow"
      assert {latest.before["effect"], latest.after["effect"]} == {"allow", "deny"}
      assert latest.admin_id == admin.id
    end

    @tag req: "RP-04"
    test "RP-04 unset removes the setting; unchanged settings write nothing", %{
      admin: admin,
      team: team,
      news: news
    } do
      set!(admin, team, news, :view, :allow)
      count = length(Audit.list_entries())

      set!(admin, team, news, :view, :allow)
      assert length(Audit.list_entries()) == count

      set!(admin, team, news, :view, :unset)
      assert Access.permissions(news) == %{}
      assert [%{after: %{"effect" => "unset"}} | _] = Audit.list_entries()
    end

    @tag req: "RP-04"
    test "RP-04 the server-wide settings are listed separately", %{admin: admin, team: team} do
      set!(admin, team, :server, :start, :allow)
      server = Access.permissions(:server)

      assert server[{team.id, :start}] == :allow
      assert server[{Access.built_in_role!(:guest).id, :view}] == :allow
      assert [%{after: %{"category" => "(server)"}} | _] = Audit.list_entries()
    end

    @tag req: "RP-04"
    test "RP-04 deleting a category or a role removes its settings", %{
      admin: admin,
      team: team,
      news: news,
      general: general
    } do
      set!(admin, team, news, :post, :allow)
      set!(admin, team, general, :post, :allow)

      {:ok, _} = Forum.delete_category(admin, news)

      assert Repo.aggregate(
               from(p in CategoryPermission, where: p.category_id == ^news.id),
               :count
             ) == 0

      Repo.delete!(team)

      assert Repo.aggregate(from(p in CategoryPermission, where: p.role_id == ^team.id), :count) ==
               0
    end
  end
end

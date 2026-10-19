# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ForumCategoriesTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Audit
  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Forum.Category

  setup do
    %{admin: user_with_role_fixture(:administrator)}
  end

  defp slugs, do: Enum.map(Forum.list_categories(), & &1.slug)

  defp create!(admin, name, attrs \\ %{}) do
    {:ok, category} = Forum.create_category(admin, Map.put(attrs, "name", name))
    category
  end

  describe "create_category/2" do
    @tag req: "RP-03"
    test "RP-03 categories are created in order, with a slug made from the name", %{admin: admin} do
      announcements = create!(admin, "Announcements", %{"description" => "News from the team"})
      create!(admin, "General")
      create!(admin, "Help & Support")

      assert announcements.slug == "announcements"
      assert announcements.description == "News from the team"
      assert slugs() == ~w(announcements general help-support)
      assert Enum.map(Forum.list_categories(), & &1.position) == [0, 1, 2]
    end

    @tag req: "RP-03"
    test "RP-03 FD-01 every category gets a stable URI at creation", %{admin: admin} do
      category = create!(admin, "General")
      assert category.uri == Application.fetch_env!(:idejo, :base_uri) <> "/c/" <> category.id
    end

    @tag req: "RP-03"
    test "RP-03 slugs drop accents, avoid clashes and can be chosen", %{admin: admin} do
      assert create!(admin, "Café & Thé").slug == "cafe-the"
      assert create!(admin, "General").slug == "general"
      assert create!(admin, "General!").slug == "general-2"
      assert create!(admin, "???").slug == "category"
      assert create!(admin, "Help", %{"slug" => "aide"}).slug == "aide"
      assert create!(admin, "Blank slug", %{"slug" => "  "}).slug == "blank-slug"
    end

    @tag req: "RP-03"
    test "RP-03 a chosen slug must be well formed and free", %{admin: admin} do
      create!(admin, "Help", %{"slug" => "aide"})

      for {slug, error} <- [
            {"Has Caps", "may only contain lowercase letters, digits and single dashes"},
            {"double--dash", "may only contain lowercase letters, digits and single dashes"},
            {"aide", "is already used by another category"},
            {String.duplicate("a", 61), "should be at most 60 character(s)"}
          ] do
        assert {:error, changeset} =
                 Forum.create_category(admin, %{"name" => "X", "slug" => slug})

        assert error in errors_on(changeset).slug
      end
    end

    @tag req: "RP-03"
    test "RP-03 a name is required and short; descriptions are optional and short", %{
      admin: admin
    } do
      assert {:error, changeset} = Forum.create_category(admin, %{"name" => " "})
      assert "can't be blank" in errors_on(changeset).name

      long = %{"name" => String.duplicate("n", 81), "description" => String.duplicate("d", 501)}
      assert {:error, changeset} = Forum.create_category(admin, long)
      assert "should be at most 80 character(s)" in errors_on(changeset).name
      assert "should be at most 500 character(s)" in errors_on(changeset).description

      assert create!(admin, "Bare", %{"description" => ""}).description == ""
    end

    @tag req: "RP-03"
    test "RP-03 one level only: no parent is ever set", %{admin: admin} do
      assert create!(admin, "General", %{"parent_id" => Ecto.UUID.generate()}).parent_id == nil
    end

    @tag req: "RP-03"
    test "RP-03 creating is audited (SP-06) and recorded as an activity (FD-02)", %{admin: admin} do
      category = create!(admin, "General")

      assert [%{change: "category.create", admin_id: admin_id, before: nil, after: after_}] =
               Audit.list_entries()

      assert admin_id == admin.id
      assert after_["slug"] == "general"

      assert [%Activity{verb: "create", actor_uri: actor, payload: payload}] =
               Repo.all(from a in Activity, where: a.object_uri == ^category.uri)

      assert actor == admin.uri
      assert payload == %{"type" => "Group", "name" => "General", "slug" => "general"}
    end
  end

  describe "update_category/3" do
    @tag req: "RP-03"
    test "RP-03 renaming keeps the slug, so links keep working", %{admin: admin} do
      category = create!(admin, "Help")

      assert {:ok, renamed} =
               Forum.update_category(admin, category, %{
                 "name" => "Help & Support",
                 "description" => "Ask here",
                 "slug" => "changed"
               })

      assert {renamed.name, renamed.description, renamed.slug} ==
               {"Help & Support", "Ask here", "help"}

      assert Forum.get_category_by_slug("help").id == category.id

      assert [
               %{
                 change: "category.update",
                 before: %{"name" => "Help"},
                 after: %{"name" => "Help & Support"}
               }
               | _
             ] =
               Audit.list_entries()

      assert Repo.exists?(
               from a in Activity, where: a.object_uri == ^category.uri and a.verb == "update"
             )
    end

    @tag req: "RP-03"
    test "RP-03 an unchanged save writes nothing", %{admin: admin} do
      category = create!(admin, "Help")
      count = length(Audit.list_entries())
      assert {:ok, _} = Forum.update_category(admin, category, %{"name" => "Help"})
      assert length(Audit.list_entries()) == count
    end
  end

  describe "move_category/3" do
    @tag req: "RP-03"
    test "RP-03 categories move up and down, audited with the whole order", %{admin: admin} do
      a = create!(admin, "A")
      _b = create!(admin, "B")
      c = create!(admin, "C")

      assert {:ok, _} = Forum.move_category(admin, c, :up)
      assert slugs() == ~w(a c b)
      assert {:ok, _} = Forum.move_category(admin, a, :down)
      assert slugs() == ~w(c a b)

      assert [
               %{
                 change: "category.reorder",
                 before: %{"order" => ~w(a c b)},
                 after: %{"order" => ~w(c a b)}
               }
               | _
             ] =
               Audit.list_entries()
    end

    @tag req: "RP-03"
    test "RP-03 the first cannot go up and the last cannot go down", %{admin: admin} do
      a = create!(admin, "A")
      b = create!(admin, "B")

      assert {:error, :at_edge} = Forum.move_category(admin, a, :up)
      assert {:error, :at_edge} = Forum.move_category(admin, b, :down)
      assert slugs() == ~w(a b)
    end
  end

  describe "delete_category/2" do
    @tag req: "RP-03"
    test "RP-03 deleting closes the gap, audited and recorded", %{admin: admin} do
      _a = create!(admin, "A")
      b = create!(admin, "B")
      _c = create!(admin, "C")

      assert {:ok, _} = Forum.delete_category(admin, b)

      assert slugs() == ~w(a c)
      assert Enum.map(Forum.list_categories(), & &1.position) == [0, 1]
      refute Repo.get(Category, b.id)

      assert [%{change: "category.delete", before: %{"slug" => "b"}, after: nil} | _] =
               Audit.list_entries()

      assert Repo.exists?(
               from a in Activity, where: a.object_uri == ^b.uri and a.verb == "delete"
             )
    end

    @tag req: "RP-03"
    test "RP-03 a deleted category's slug can be used again", %{admin: admin} do
      {:ok, _} = Forum.delete_category(admin, create!(admin, "General"))
      assert create!(admin, "General").slug == "general"
    end
  end

  @tag req: "RP-03"
  test "RP-03 slugify/1 makes lowercase ASCII words joined by dashes" do
    assert Forum.slugify("  Hello, World!  ") == "hello-world"
    assert Forum.slugify("Ünïcödé Ça va") == "unicode-ca-va"
    assert Forum.slugify(String.duplicate("long ", 30)) |> String.length() <= 50
    assert Forum.slugify("") == "category"
  end
end

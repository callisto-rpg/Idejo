# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.CategoryIconsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Forum.{Category, CategoryIcons}
  alias IdejoWeb.TopicComponents

  defp flatten(shapes),
    do: Enum.flat_map(shapes, fn {tag, attrs, children} -> [{tag, attrs} | flatten(children)] end)

  defp mark(category), do: render_component(&TopicComponents.category_mark/1, category: category)

  @tag req: "RP-03"
  test "RP-03 the icon set: 63 icons in three sets, plain shapes only" do
    assert length(CategoryIcons.ids()) == 63
    assert Enum.uniq(CategoryIcons.ids()) == CategoryIcons.ids()
    assert Enum.map(CategoryIcons.groups(), &elem(&1, 0)) == [:topics, :sports, :more]

    allowed = ~w(rect circle ellipse path g)a

    for id <- CategoryIcons.ids() do
      shapes = CategoryIcons.shapes(id, "#3366ff")
      assert [{"rect", tile, []} | _] = shapes
      assert tile[:fill] == "#3366ff"

      for {tag, attrs} <- flatten(shapes) do
        assert String.to_existing_atom(tag) in allowed
        refute Enum.any?(attrs, fn {_, value} -> value =~ "{{" end)
        assert Enum.all?(Keyword.keys(attrs), &(&1 not in [:style, :href]))
      end

      assert IdejoWeb.CategoryIconNames.name(id) != id
    end

    # The shapes take white or near-black, whichever reads better on the tile.
    assert CategoryIcons.contrast("#1a1a8c") == "#ffffff"
    assert CategoryIcons.contrast("#ce9200") == "#111111"
  end

  @tag req: "RP-03"
  test "RP-03 administrators give a category an icon and a colour, audited" do
    admin = user_with_role_fixture(:administrator)

    {:ok, category} =
      Forum.create_category(admin, %{
        "name" => "Garden",
        "icon" => "plants",
        "colour" => " #0FA05C "
      })

    assert {category.icon, category.colour} == {"plants", "#0fa05c"}

    {:error, changeset} =
      Forum.update_category(admin, category, %{"icon" => "nothing", "colour" => "green"})

    assert "is not one of the icons" in errors_on(changeset).icon
    assert "must look like #3366ff" in errors_on(changeset).colour

    {:ok, changed} = Forum.update_category(admin, category, %{"icon" => "soccer", "colour" => ""})
    assert {changed.icon, changed.colour} == {"soccer", nil}

    entry = Enum.find(Audit.list_entries(), &(&1.change == "category.update"))
    assert entry.before["icon"] == "plants"
    assert entry.after == Map.merge(entry.before, %{"icon" => "soccer", "colour" => nil})
  end

  @tag req: "RP-03"
  test "RP-03 the mark: the icon on the colour, the initial on the colour, or the tint" do
    id = Ecto.UUID.generate()

    html = mark(%Category{id: id, name: "Garden", icon: "plants", colour: "#0fa05c"})
    assert html =~ ~s(viewBox="0 0 32 32")
    assert html =~ ~s(fill="#0fa05c")
    assert html =~ ~s(aria-hidden="true")

    # An icon without a colour takes the tint its id gives it.
    assert mark(%Category{id: id, name: "Garden", icon: "plants"}) =~ CategoryIcons.tint(id)

    html = mark(%Category{id: id, name: "garden", colour: "#ffffff"})
    assert html =~ ~s(rx="7" fill="#ffffff")
    assert html =~ ~r/fill="#111111"[^>]*>\s*G\s*</

    assert mark(%Category{id: id, name: "Garden"}) =~ ~s(class="category-mark hue-)
  end
end

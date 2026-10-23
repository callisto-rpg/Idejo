# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ForumTagsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Audit
  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Forum.Tags
  alias Idejo.Moderation.Action

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, help: help}
  end

  # Tag names are unique across the server: each test's tags have names of their own.
  defp tag!(admin, name, category \\ nil) do
    attrs = %{"name" => "#{name} #{System.unique_integer([:positive])}"}
    attrs = if category, do: Map.put(attrs, "category_id", category.id), else: attrs
    {:ok, tag} = Tags.create_tag(admin, attrs)
    tag
  end

  defp topic!(category, title, tags) do
    {:ok, topic} =
      Forum.create_topic(user_fixture(), category, %{
        "title" => title,
        "body" => "Hi",
        "tag_ids" => Enum.map(tags, & &1.id)
      })

    topic
  end

  defp tag_names(topic),
    do:
      topic
      |> Repo.reload!()
      |> Repo.preload(tags: Tags.ordered())
      |> Map.get(:tags)
      |> Enum.map(& &1.name)

  @tag req: "TP-19"
  test "TP-19 administrators make tags for every category or for one, audited", %{
    admin: admin,
    general: general,
    help: help
  } do
    everywhere = tag!(admin, "Question")
    seeds = tag!(admin, "Seeds", general)

    assert everywhere.category_id == nil
    assert seeds.category_id == general.id
    assert seeds.slug =~ ~r/^seeds-\d+$/

    assert Enum.map(Tags.available_tags(general), & &1.id) |> Enum.sort() ==
             Enum.sort([everywhere.id, seeds.id])

    assert Enum.map(Tags.available_tags(help), & &1.id) == [everywhere.id]

    # Names are unique ignoring case, and the Archive takes no tags.
    {:error, changeset} = Tags.create_tag(admin, %{"name" => String.upcase(seeds.name)})
    assert "is already used by another tag" in errors_on(changeset).name

    assert Enum.find(Audit.list_entries(), &(&1.change == "tag.create")).after["name"] ==
             seeds.name

    {:ok, archive} = Forum.archive_category(admin)
    {:error, changeset} = Tags.create_tag(admin, %{"name" => "Old", "category_id" => archive.id})
    assert errors_on(changeset).category_id != []
  end

  @tag req: "TP-19"
  test "TP-19 renaming keeps the slug; deleting takes the tag off its topics, audited", %{
    admin: admin,
    general: general
  } do
    tag = tag!(admin, "Bug")
    other = tag!(admin, "Idea")
    topic = topic!(general, "Crash", [tag, other])

    {:ok, renamed} = Tags.update_tag(admin, tag, %{"name" => "Defect #{tag.slug}"})
    assert renamed.slug == tag.slug
    assert [%{change: "tag.update"} | _] = Audit.list_entries()

    {:ok, _} = Tags.delete_tag(admin, renamed)
    assert tag_names(topic) == [other.name]
    assert [%{change: "tag.delete", before: %{"topics" => 1}} | _] = Audit.list_entries()
  end

  @tag req: "TP-19"
  test "TP-19 starting a topic takes at least one of its category's tags when it has any", %{
    admin: admin,
    general: general,
    help: help
  } do
    user = user_fixture()
    attrs = %{"title" => "Plans", "body" => "Hi"}

    # No tags yet: none needed.
    assert {:ok, _} = Forum.create_topic(user, general, attrs)

    everywhere = tag!(admin, "Question")
    seeds = tag!(admin, "Seeds", general)
    roots = tag!(admin, "Roots", help)

    assert {:error, changeset} = Forum.create_topic(user, general, attrs)
    assert "choose at least one tag" in errors_on(changeset).tag_ids

    # Another category's tag is refused.
    assert {:error, changeset} =
             Forum.create_topic(user, general, Map.put(attrs, "tag_ids", [roots.id]))

    assert "are not tags of this category" in errors_on(changeset).tag_ids

    {:ok, topic} =
      Forum.create_topic(user, general, Map.put(attrs, "tag_ids", ["", seeds.id, everywhere.id]))

    assert Enum.sort(tag_names(topic)) == Enum.sort([seeds.name, everywhere.name])

    activity = Repo.get_by!(Activity, object_uri: topic.uri, verb: "create")
    assert Enum.sort(activity.payload["tag"]) == Enum.sort([seeds.name, everywhere.name])
  end

  @tag req: "TP-19"
  test "TP-19 moderators edit a topic's tags by default, logged; the grid gives the right", %{
    admin: admin,
    general: general
  } do
    first = tag!(admin, "Question")
    second = tag!(admin, "Seeds", general)
    topic = topic!(general, "Plans", [first])
    member = user_fixture()
    moderator = user_with_role_fixture(:moderator)

    assert {:error, :forbidden} = Forum.set_topic_tags(member, topic, [second.id])
    assert {:error, :tag_required} = Forum.set_topic_tags(moderator, topic, [])

    assert {:error, :invalid_tags} =
             Forum.set_topic_tags(moderator, topic, [Ecto.UUID.generate()])

    {:ok, _} = Forum.set_topic_tags(moderator, topic, [second.id], "Better fit")
    assert tag_names(topic) == [second.name]

    entry = Repo.get_by!(Action, action: "topic.tags", target_id: topic.id)
    assert entry.reason == "Better fit"
    assert entry.details == %{"from" => [first.name], "to" => [second.name]}

    # Members get it through the permission grid.
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), general, :tag, :allow)
    assert {:ok, _} = Forum.set_topic_tags(member, topic, [first.id, second.id])

    # Archived topics keep their tags.
    topic |> Ecto.Changeset.change(state: "archived") |> Repo.update!()
    assert {:error, :archived} = Forum.set_topic_tags(moderator, topic, [first.id])
  end

  @tag req: "TP-19"
  test "TP-19 a moved topic keeps the tags for every category, not the old category's", %{
    admin: admin,
    general: general,
    help: help
  } do
    everywhere = tag!(admin, "Question")
    seeds = tag!(admin, "Seeds", general)
    topic = topic!(general, "Plans", [everywhere, seeds])

    {:ok, _} = Forum.move_topic(admin, topic, help)
    assert tag_names(topic) == [everywhere.name]

    # Deleting a category deletes its own tags.
    {:ok, _} = Forum.delete_category(admin, general)
    refute Repo.get(Idejo.Forum.Tag, seeds.id)
  end

  @tag req: "TP-19"
  test "TP-19 filtering by tags lists topics carrying all of them, that the user may view", %{
    admin: admin,
    general: general,
    help: help
  } do
    a = tag!(admin, "Alpha")
    b = tag!(admin, "Beta")
    hidden = tag!(admin, "Staff", help)

    both = topic!(general, "Both", [a, b])
    _only_a = topic!(general, "Only A", [a])
    in_help = topic!(help, "Help both", [a, b, hidden])

    {topics, false} = Tags.list_tagged_topics(nil, [a, b])
    assert Enum.map(topics, & &1.id) |> Enum.sort() == Enum.sort([both.id, in_help.id])

    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), help, :view, :deny)
    assert {[%{id: id}], false} = Tags.list_tagged_topics(nil, [a, b])
    assert id == both.id

    # The hidden category's tag is not offered to filter by.
    refute hidden.id in Enum.map(Tags.list_viewable_tags(nil), & &1.id)
    assert hidden.id in Enum.map(Tags.list_viewable_tags(user_fixture()), & &1.id)

    assert Tags.list_tagged_topics(nil, []) == {[], false}
  end

  # The Operator toggle's Or (steward decision, 2026-10-24).
  @tag req: "TP-19"
  test "TP-19 filtering with match: :any lists topics carrying at least one of the tags", %{
    admin: admin,
    general: general
  } do
    a = tag!(admin, "Alpha")
    b = tag!(admin, "Beta")
    c = tag!(admin, "Gamma")

    both = topic!(general, "Both", [a, b])
    only_a = topic!(general, "Only A", [a])
    only_b = topic!(general, "Only B", [b])
    _only_c = topic!(general, "Only C", [c])

    {topics, false} = Tags.list_tagged_topics(nil, [a, b], match: :any)
    assert Enum.map(topics, & &1.id) |> Enum.sort() == Enum.sort([both.id, only_a.id, only_b.id])

    {topics, false} = Tags.list_tagged_topics(nil, [a, b], match: :all)
    assert Enum.map(topics, & &1.id) == [both.id]
  end
end

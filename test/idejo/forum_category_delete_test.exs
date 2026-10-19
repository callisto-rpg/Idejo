# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ForumCategoryDeleteTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Audit
  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Forum.{Category, Topic}

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, old} = Forum.create_category(admin, %{"name" => "Old"})
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture()

    topics =
      for title <- ["One", "Two"] do
        {:ok, topic} = Forum.create_topic(member, old, %{"title" => title, "body" => "Hi"})
        topic
      end

    %{admin: admin, old: old, general: general, member: member, topics: topics}
  end

  defp reload(topics), do: Enum.map(topics, &Repo.reload!/1)

  @tag req: "RP-03"
  test "RP-03 deleting a category with topics needs to know where they go", %{
    admin: admin,
    old: old
  } do
    assert Forum.delete_category(admin, old) == {:error, :has_topics}
    assert Repo.reload(old)
  end

  @tag req: "RP-03"
  test "RP-03 the topics can move to another category, as they are", %{
    admin: admin,
    old: old,
    general: general,
    topics: topics
  } do
    assert {:ok, _} = Forum.delete_category(admin, old, topics: {:move, general})

    refute Repo.reload(old)
    assert Enum.all?(reload(topics), &(&1.category_id == general.id and &1.state == "open"))

    [entry | _] = Audit.list_entries()
    assert entry.change == "category.delete"
    assert entry.before["topics"] == %{"count" => 2, "moved_to" => "general"}

    for topic <- topics do
      assert [%Activity{target_uri: target}] =
               Repo.all(
                 from a in Activity, where: a.object_uri == ^topic.uri and a.verb == "update"
               )

      assert target == general.uri
    end
  end

  @tag req: "RP-03"
  test "RP-03 they cannot move into the category being deleted or the Archive", %{
    admin: admin,
    old: old
  } do
    assert Forum.delete_category(admin, old, topics: {:move, old}) == {:error, :invalid_target}
    {:ok, archive} = Forum.archive_category(admin)

    assert Forum.delete_category(admin, old, topics: {:move, archive}) ==
             {:error, :invalid_target}

    assert Repo.reload(old)
  end

  @tag req: "TP-14"
  test "TP-14 archiving moves the topics, archived, to the Archive category", %{
    admin: admin,
    old: old,
    topics: topics
  } do
    refute Repo.exists?(from c in Category, where: c.archive)
    assert {:ok, _} = Forum.delete_category(admin, old, topics: :archive)

    archive = Repo.one!(from c in Category, where: c.archive)
    assert archive.name == "Archive"
    assert archive.slug == "archive"
    assert Enum.all?(reload(topics), &(&1.category_id == archive.id and &1.state == "archived"))

    [entry | _] = Audit.list_entries()
    assert entry.before["topics"] == %{"count" => 2, "archived_in" => "archive"}
  end

  @tag req: "TP-14"
  test "TP-14 the Archive is hidden from everyone by default, and can be shown in the grid", %{
    admin: admin,
    old: old,
    member: member,
    topics: [topic | _]
  } do
    {:ok, team} = Access.create_role(admin, %{"name" => "Team"})
    {:ok, _} = Forum.delete_category(admin, old, topics: :archive)
    {:ok, archive} = Forum.archive_category(admin)

    for user <- [nil, member, user_with_role_fixture(:moderator)] do
      refute Access.can?(user, :view, archive)
      assert Forum.get_viewable_topic(user, topic.id) == nil
    end

    assert Access.can?(admin, :view, archive)
    assert Forum.get_viewable_topic(admin, topic.id)

    {:ok, _} = Access.set_permission(admin, team, archive, :view, :allow)
    team_member = user_fixture()
    {:ok, _} = Access.assign_role(admin, team_member, team)
    assert Forum.get_viewable_topic(team_member, topic.id)
  end

  @tag req: "TP-14"
  test "TP-14 there is one Archive, reused, never deleted and never given new topics", %{
    admin: admin,
    old: old,
    general: general
  } do
    {:ok, _} = Forum.delete_category(admin, old, topics: :archive)
    {:ok, archive} = Forum.archive_category(admin)

    {:ok, other} = Forum.create_category(admin, %{"name" => "Other"})
    {:ok, _} = Forum.create_topic(user_fixture(), other, %{"title" => "Three", "body" => "Hi"})
    {:ok, _} = Forum.delete_category(admin, other, topics: :archive)

    assert Repo.aggregate(from(c in Category, where: c.archive), :count) == 1
    assert Repo.aggregate(from(t in Topic, where: t.category_id == ^archive.id), :count) == 3

    assert Forum.delete_category(admin, archive) == {:error, :archive}

    assert Forum.create_topic(admin, archive, %{"title" => "New", "body" => "x"}) ==
             {:error, :forbidden}

    refute Forum.can_start_topic?(admin, archive)
    assert Forum.can_start_topic?(admin, general)
  end

  @tag req: "TP-14"
  test "TP-14 the Archive takes a free slug when archive is taken", %{admin: admin, old: old} do
    {:ok, _} = Forum.create_category(admin, %{"name" => "Archive", "slug" => "archive"})
    {:ok, _} = Forum.delete_category(admin, old, topics: :archive)
    assert Repo.one!(from c in Category, where: c.archive).slug == "archive-2"
  end

  @tag req: "RP-03"
  test "RP-03 an empty category still deletes without a choice", %{admin: admin, general: general} do
    assert {:ok, _} = Forum.delete_category(admin, general)
  end
end

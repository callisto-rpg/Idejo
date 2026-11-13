# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.TopicPermissionsTest do
  @moduledoc """
  Topic permissions (steward request, 2026-11-13; `Idejo.Access.set_topic_permission/5`): a
  topic allows or denies view, post, moderate and edit-tags to a role over its category,
  for those who moderate it, logged; and pinned messages (`Idejo.Messages.set_pinned/3`).
  """
  use Idejo.DataCase, async: true

  import Ecto.Query
  import Idejo.AccountsFixtures

  alias Idejo.{Access, Forum, Messages}
  alias Idejo.Access.Role
  alias Idejo.Forum.Topic
  alias Idejo.Moderation.Action

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    team = Repo.insert!(%Role{name: "Team", position: 4})
    member = Access.built_in_role!(:member)

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Plans", "body" => "Soon"})

    {:ok, other} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Other", "body" => "Hi"})

    %{admin: admin, general: general, team: team, member: member, topic: topic, other: other}
  end

  defp holding(role) do
    user = user_fixture()
    :ok = Access.grant_role(user, role)
    user
  end

  defp viewable_ids(user) do
    from(t in Topic, as: :topic, select: t.id)
    |> Access.where_topic_allowed(user, :view)
    |> Repo.all()
    |> MapSet.new()
  end

  test "a topic hides itself from members and opens to one role, in checks and lists", %{
    admin: admin,
    team: team,
    member: member,
    topic: topic,
    other: other
  } do
    reader = user_fixture()
    insider = holding(team)

    # Visitors hold guest, not member: each role is set apart, as in categories.
    guest = Access.built_in_role!(:guest)
    assert {:ok, :deny} = Access.set_topic_permission(admin, member, topic, :view, :deny)
    assert {:ok, :deny} = Access.set_topic_permission(admin, guest, topic, :view, :deny)
    assert {:ok, :allow} = Access.set_topic_permission(admin, team, topic, :view, :allow)

    refute Access.can?(reader, :view, topic)
    assert Access.can?(insider, :view, topic)
    assert Access.can?(admin, :view, topic)
    refute Access.can?(nil, :view, topic)
    assert Access.can?(reader, :view, other)

    refute topic.id in viewable_ids(reader)
    assert other.id in viewable_ids(reader)
    assert topic.id in viewable_ids(insider)
    assert topic.id in viewable_ids(admin)

    assert Forum.get_viewable_topic(reader, topic.id) == nil
    assert Forum.get_viewable_topic(insider, topic.id)
    assert Access.filter_allowed([reader, insider], :view, topic) == [insider]

    # Unset: the category's again.
    assert {:ok, :unset} = Access.set_topic_permission(admin, member, topic, :view, :unset)
    assert Access.can?(reader, :view, topic)
    assert topic.id in viewable_ids(reader)
  end

  test "only those who moderate the topic set it; owner and administrator take no setting", %{
    admin: admin,
    team: team,
    member: member,
    topic: topic
  } do
    assert Access.set_topic_permission(user_fixture(), member, topic, :post, :deny) ==
             {:error, :forbidden}

    owner = Access.built_in_role!(:owner)

    assert Access.set_topic_permission(admin, owner, topic, :view, :deny) ==
             {:error, :always_all_rights}

    assert {:ok, :deny} = Access.set_topic_permission(admin, member, topic, :post, :deny)
    refute Forum.can_post?(user_fixture(), topic)

    entry = Repo.one!(from a in Action, where: a.action == "topic.permission")
    assert entry.target_id == topic.id

    assert entry.details == %{
             "role" => "member",
             "right" => "post",
             "from" => "unset",
             "to" => "deny"
           }

    # A role that moderates the topic by its own setting moderates it, and sets it too.
    keeper = holding(team)
    refute Access.moderates_a_topic?(keeper)
    assert :ok =
             Access.set_topic_permissions(admin, topic, %{team.id => %{"moderate" => "allow"}})
    assert Access.can?(keeper, :moderate, topic)
    assert Access.moderates_a_topic?(keeper)
    assert Idejo.Moderation.moderator?(keeper)
    assert {:ok, :allow} = Access.set_topic_permission(keeper, member, topic, :tag, :allow)
    assert Access.topic_permissions(topic)[{member.id, :tag}] == :allow
  end

  test "category rights show what a topic without settings gives", %{
    member: member,
    topic: topic
  } do
    rights = Access.category_rights(topic)
    assert rights[{member.id, :view}] == :allow
    assert rights[{member.id, :moderate}] == :deny
  end

  test "moderators pin messages, listed oldest pin first; logged", %{
    admin: admin,
    topic: topic
  } do
    {:ok, second} = Forum.post_message(user_fixture(), topic, %{"body" => "Second"})
    [first | _] = Forum.list_messages(topic)

    assert Messages.set_pinned(user_fixture(), second, true) == {:error, :forbidden}

    assert {:ok, %{pinned_at: %DateTime{}}} = Messages.set_pinned(admin, second, true)
    assert {:ok, _} = Messages.set_pinned(admin, first, true)
    assert Enum.map(Forum.pinned_messages(topic), & &1.id) == [second.id, first.id]

    assert {:ok, %{pinned_at: nil}} = Messages.set_pinned(admin, second, false)
    assert Enum.map(Forum.pinned_messages(topic), & &1.id) == [first.id]

    actions = Repo.all(from a in Action, where: a.action in ["message.pin", "message.unpin"])
    assert length(actions) == 3
  end
end

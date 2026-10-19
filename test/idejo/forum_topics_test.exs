# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ForumTopicsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages.Message

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    %{admin: admin, general: general, member: user_fixture()}
  end

  defp attrs(overrides \\ %{}),
    do: Map.merge(%{"title" => "Hello there", "body" => "My *first* message"}, overrides)

  @tag req: "TP-01"
  test "TP-01 a member starts a topic with a title and a first message", %{
    member: member,
    general: general
  } do
    assert {:ok, %Topic{} = topic} = Forum.create_topic(member, general, attrs())

    assert topic.title == "Hello there"
    assert topic.slug == "hello-there"
    assert topic.category_id == general.id
    assert topic.author_id == member.id
    assert topic.state == "open"
    assert topic.message_count == 1
    assert topic.uri =~ ~r{/t/#{topic.id}$}

    assert [message] = Forum.list_messages(topic)
    assert message.author.id == member.id
    assert message.uri =~ ~r{/m/#{message.id}$}
  end

  @tag req: "TP-01"
  test "TP-01 the first message is stored as Markdown and sanitised HTML (FD-03)", %{
    member: member,
    general: general
  } do
    body = "My *first* message <script>alert(1)</script> [x](javascript:alert(1))"
    {:ok, topic} = Forum.create_topic(member, general, attrs(%{"body" => body}))
    [message] = Forum.list_messages(topic)

    assert message.body_md == body
    assert message.body_html =~ "<em>first</em>"
    refute message.body_html =~ "<script"
    refute message.body_html =~ "javascript:"
  end

  @tag req: "TP-01"
  test "TP-01 the first message is never open (GM-14)", %{member: member, general: general} do
    {:ok, topic} = Forum.create_topic(member, general, attrs())
    [message] = Forum.list_messages(topic)

    assert message.state == "closed"
    assert message.closed_at == message.opened_at
    assert message.closes_at == message.opened_at
  end

  @tag req: "TP-01"
  test "TP-01 the title and the first message are required", %{
    member: member,
    general: general
  } do
    assert {:error, changeset} =
             Forum.create_topic(member, general, %{"title" => "  ", "body" => " "})

    assert %{title: ["can't be blank"], body: ["can't be blank"]} = errors_on(changeset)

    long = String.duplicate("a", 151)
    assert {:error, changeset} = Forum.create_topic(member, general, attrs(%{"title" => long}))
    assert %{title: ["should be at most 150 character(s)"]} = errors_on(changeset)

    refute Repo.exists?(Topic)
  end

  @tag req: "TP-01"
  test "TP-01 starting a topic needs the start right", %{admin: admin, general: general} do
    assert Forum.create_topic(unconfirmed_user_fixture(), general, attrs()) ==
             {:error, :forbidden}

    member = Access.built_in_role!(:member)
    {:ok, _} = Access.set_permission(admin, member, general, :start, :deny)
    assert Forum.create_topic(user_fixture(), general, attrs()) == {:error, :forbidden}

    refute Repo.exists?(Topic)
    refute Repo.exists?(Message)
  end

  @tag req: "TP-01"
  test "TP-01 the topic and its first message each get a create activity (FD-02)", %{
    member: member,
    general: general
  } do
    {:ok, topic} = Forum.create_topic(member, general, attrs())
    [message] = Forum.list_messages(topic)

    assert [%Activity{verb: "create", actor_uri: actor, target_uri: target}] =
             Repo.all(from a in Activity, where: a.object_uri == ^topic.uri)

    assert actor == member.uri
    assert target == general.uri

    assert [%Activity{target_uri: topic_uri}] =
             Repo.all(from a in Activity, where: a.object_uri == ^message.uri)

    assert topic_uri == topic.uri
  end

  @tag req: "TP-01"
  test "TP-01 a title without letters or digits gets the slug topic", %{
    member: member,
    general: general
  } do
    {:ok, topic} = Forum.create_topic(member, general, attrs(%{"title" => "¿¡!?"}))
    assert topic.slug == "topic"
  end

  @tag req: "TP-01"
  test "TP-01 topics are read only where the category can be viewed", %{
    admin: admin,
    member: member,
    general: general
  } do
    {:ok, topic} = Forum.create_topic(member, general, attrs())
    assert Forum.get_viewable_topic(nil, topic.id).id == topic.id

    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), general, :view, :deny)
    assert Forum.get_viewable_topic(nil, topic.id) == nil
    assert Forum.get_viewable_topic(member, topic.id).id == topic.id
    assert Forum.get_viewable_topic(nil, "not-a-uuid") == nil
  end

  @tag req: "RP-03"
  test "RP-03 a category with topics is not deleted", %{
    admin: admin,
    member: member,
    general: general
  } do
    {:ok, _} = Forum.create_topic(member, general, attrs())
    assert Forum.delete_category(admin, general) == {:error, :has_topics}
    assert Forum.get_category_by_slug("general")
  end
end

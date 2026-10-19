# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ForumRepliesTest do
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
    starter = user_fixture(%{display_name: "Sam Starter"})

    {:ok, topic} =
      Forum.create_topic(starter, general, %{"title" => "Plans", "body" => "What **next**?"})

    [first] = Forum.list_messages(topic)
    %{admin: admin, general: general, topic: topic, first: first, member: user_fixture()}
  end

  @tag req: "TP-08"
  test "TP-08 a reply references one message of the topic", %{
    topic: topic,
    first: first,
    member: member
  } do
    assert {:ok, reply} =
             Forum.post_message(member, topic, %{"body" => "Lunch", "reply_to_id" => first.id})

    assert reply.reply_to_id == first.id
    assert reply.topic_id == topic.id
    assert reply.state == "closed"

    [_, listed] = Forum.list_messages(topic)
    assert listed.reply_to.id == first.id
    assert listed.reply_to.author.display_name == "Sam Starter"
  end

  @tag req: "TP-08"
  test "TP-08 replies stay in the topic's one flow: no side threads", %{
    topic: topic,
    first: first,
    member: member
  } do
    {:ok, a} = Forum.post_message(member, topic, %{"body" => "A", "reply_to_id" => first.id})
    {:ok, b} = Forum.post_message(member, topic, %{"body" => "B"})
    {:ok, c} = Forum.post_message(member, topic, %{"body" => "C", "reply_to_id" => a.id})

    assert Enum.map(Forum.list_messages(topic), & &1.id) == [first.id, a.id, b.id, c.id]
  end

  @tag req: "TP-08"
  test "TP-08 posting moves the topic on and is recorded", %{
    topic: topic,
    first: first,
    member: member
  } do
    {:ok, reply} = Forum.post_message(member, topic, %{"body" => "Hi", "reply_to_id" => first.id})

    topic = Repo.reload!(topic)
    assert topic.message_count == 2
    assert DateTime.compare(topic.last_activity_at, first.opened_at) == :gt

    assert [%Activity{target_uri: target, payload: %{"inReplyTo" => in_reply_to}}] =
             Repo.all(from a in Activity, where: a.object_uri == ^reply.uri)

    assert target == topic.uri
    assert in_reply_to == first.uri
  end

  @tag req: "TP-08"
  test "TP-08 a reply cannot reference a message of another topic", %{
    general: general,
    topic: topic,
    member: member
  } do
    {:ok, other} = Forum.create_topic(member, general, %{"title" => "Other", "body" => "x"})
    [elsewhere] = Forum.list_messages(other)

    for bad <- [elsewhere.id, Ecto.UUID.generate(), "nope"] do
      assert {:error, changeset} =
               Forum.post_message(member, topic, %{"body" => "Hi", "reply_to_id" => bad})

      assert %{body: ["replies to a message that is not in this topic"]} = errors_on(changeset)
    end

    assert Repo.reload!(topic).message_count == 1
  end

  @tag req: "TP-08"
  test "TP-08 posting needs the post right and an open topic", %{
    admin: admin,
    general: general,
    topic: topic,
    member: member
  } do
    assert Forum.post_message(unconfirmed_user_fixture(), topic, %{"body" => "x"}) ==
             {:error, :forbidden}

    topic |> Ecto.Changeset.change(state: "locked") |> Repo.update!()
    assert Forum.post_message(member, topic, %{"body" => "x"}) == {:error, :forbidden}
    assert Forum.post_message(admin, topic, %{"body" => "x"}) == {:error, :forbidden}

    topic |> Ecto.Changeset.change(state: "open") |> Repo.update!()
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), general, :post, :deny)
    assert Forum.post_message(member, topic, %{"body" => "x"}) == {:error, :forbidden}

    assert Repo.aggregate(Message, :count) == 1
    assert Repo.reload!(topic).message_count == 1
    refute Repo.exists?(from t in Topic, where: t.message_count > 1)
  end

  @tag req: "TP-08"
  test "TP-08 archived topics take no messages", %{
    admin: admin,
    general: general,
    topic: topic,
    member: member
  } do
    {:ok, _} = Forum.delete_category(admin, general, topics: :archive)
    topic = Repo.reload!(topic)
    assert topic.state == "archived"
    assert Forum.post_message(admin, topic, %{"body" => "x"}) == {:error, :forbidden}
    refute Forum.can_post?(member, topic)
  end

  @tag req: "TP-08"
  test "TP-08 the excerpt is short plain text", %{first: first} do
    assert Forum.excerpt(first) == "What next?"

    long = %Message{body_html: Idejo.Markdown.to_html(String.duplicate("word ", 60))}
    excerpt = Forum.excerpt(long)
    assert String.length(excerpt) <= 141
    assert String.ends_with?(excerpt, "word…")
  end
end

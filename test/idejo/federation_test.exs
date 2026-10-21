# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.FederationTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Messages

  @base Application.compile_env!(:idejo, :base_uri)

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, category} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture(%{password: "the author's passphrase"})

    {:ok, topic} =
      Forum.create_topic(author, category, %{"title" => "Plans", "body" => "First **words**"})

    [first] = Forum.list_messages(topic)
    %{admin: admin, category: category, author: author, topic: topic, first: first}
  end

  defp activities_of(uri) do
    Repo.all(from a in Activity, where: a.object_uri == ^uri, order_by: [asc: a.id])
  end

  @tag req: "FD-01"
  test "FD-01 users, categories, topics and messages get a unique URI that never changes", ctx do
    %{admin: admin, category: category, author: author, topic: topic, first: first} = ctx

    assert author.uri == "#{@base}/u/#{author.id}"
    assert category.uri == "#{@base}/c/#{category.id}"
    assert topic.uri == "#{@base}/t/#{topic.id}"
    assert first.uri == "#{@base}/m/#{first.id}"

    # Unique: the ids are UUIDv7, and no two records share a URI.
    uris = [admin.uri, author.uri, category.uri, topic.uri, first.uri]
    assert Enum.uniq(uris) == uris
    for record <- [author, category, topic, first], do: assert(uuid_version(record.id) == 7)

    # Stable: renaming a category or a topic, or changing a profile, keeps the URI.
    {:ok, renamed} = Forum.update_category(admin, category, %{"name" => "Talk"})
    assert renamed.uri == category.uri
    {:ok, profile} = Accounts.update_user_profile(author, %{"display_name" => "Someone else"})
    assert profile.uri == author.uri

    {:ok, other} = Forum.create_category(admin, %{"name" => "Elsewhere"})
    {:ok, moved} = Forum.move_topic(admin, topic, other, "Better there")
    assert moved.uri == topic.uri
  end

  defp uuid_version(id) do
    <<_::48, version::4, _::bitstring>> = Ecto.UUID.dump!(id)
    version
  end

  @tag req: "FD-02"
  test "FD-02 creating, changing and deleting record activities with actor, object and target",
       ctx do
    %{admin: admin, category: category, author: author, topic: topic, first: first} = ctx

    assert [%{verb: "create", actor_uri: actor, target_uri: target}] = activities_of(topic.uri)
    assert actor == author.uri
    assert target == category.uri

    assert [%{verb: "create", actor_uri: ^actor, target_uri: topic_uri}] =
             activities_of(first.uri)

    assert topic_uri == topic.uri

    {:ok, reply} = Forum.post_message(author, topic, %{"body" => "Second thoughts"})
    {:ok, edited} = Messages.edit(author, reply, "Third thoughts")
    assert [%{verb: "create"}, %{verb: "update", actor_uri: ^actor}] = activities_of(edited.uri)

    moderator = user_with_role_fixture(:moderator)
    {:ok, _} = Messages.delete_as_moderator(moderator, edited, "Off topic")

    assert %{verb: "delete", actor_uri: by, target_uri: ^topic_uri} =
             List.last(activities_of(edited.uri))

    assert by == moderator.uri

    {:ok, _} = Forum.update_category(admin, category, %{"name" => "Talk"})
    assert %{verb: "update", actor_uri: admin_uri} = List.last(activities_of(category.uri))
    assert admin_uri == admin.uri

    {:ok, _} = Accounts.delete_user(author, "the author's passphrase")
    assert %{verb: "delete", actor_uri: ^actor} = List.last(activities_of(author.uri))
  end

  @tag req: "FD-03"
  test "FD-03 messages are stored as Markdown and as sanitised HTML", ctx do
    %{author: author, topic: topic, first: first} = ctx

    assert first.body_md == "First **words**"
    assert first.body_html =~ "<strong>words</strong>"

    {:ok, message} =
      Forum.post_message(author, topic, %{
        "body" => ~S|Hi <script>alert(1)</script> [x](javascript:alert(1)) <b onclick="x">b</b>|
      })

    stored = Repo.reload!(message)
    assert stored.body_md =~ "<script>alert(1)</script>"
    refute stored.body_html =~ "<script"
    refute stored.body_html =~ "javascript:"
    refute stored.body_html =~ "onclick"
  end
end

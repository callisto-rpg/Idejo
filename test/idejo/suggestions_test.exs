# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.SuggestionsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Forum.Tags
  alias Idejo.Reading
  alias Idejo.Suggestions

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff room"})

    for role <- [:guest, :member],
        do:
          {:ok, _} =
            Access.set_permission(admin, Access.built_in_role!(role), staff, :view, :deny)

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, staff: staff, me: user_fixture()}
  end

  defp topic!(user, category, title) do
    {:ok, topic} = Forum.create_topic(user, category, %{"title" => title, "body" => "Hi"})
    topic
  end

  defp ids(items), do: Enum.map(items, & &1.id)

  @tag req: "TP-10"
  test "TP-10 @ suggests who wrote here, then in topics read lately; never oneself", %{
    general: general,
    me: me
  } do
    here = user_fixture()
    there = user_fixture()
    _stranger = user_fixture()
    topic = topic!(here, general, "Here")
    other = topic!(there, general, "There")
    {:ok, _} = Forum.post_message(me, topic, %{"body" => "Me too"})
    :ok = Reading.mark_read(me, other)

    assert ids(Suggestions.suggest(me, :user, "", topic_id: topic.id)) == [here.id, there.id]
  end

  @tag req: "TP-10"
  test "TP-10 typing narrows by username or display name, recent people first", %{
    general: general,
    me: me
  } do
    robert = user_fixture(%{username: unique_username("robert"), display_name: "Bob"})
    robin = user_fixture(%{username: unique_username("hood"), display_name: "Robin Hood"})
    roberta = user_fixture(%{username: unique_username("x"), display_name: "Anna Roberta"})
    _ruth = user_fixture(%{username: unique_username("ruth"), display_name: "Ruth"})
    topic = topic!(robin, general, "Woods")

    found = Suggestions.suggest(me, :user, "Rob", topic_id: topic.id)
    assert hd(found).id == robin.id
    assert Enum.sort(ids(found)) == Enum.sort([robert.id, robin.id, roberta.id])

    assert Suggestions.suggest(nil, :user, "rob") == []
  end

  @tag req: "TP-10"
  test "TP-10 #, / and $ suggest only what the user may view, recently read first", %{
    admin: admin,
    general: general,
    staff: staff,
    me: me
  } do
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})
    # Topics first: once tags exist, starting a topic takes one (TP-19).
    old = topic!(admin, general, "Garden plans")
    hidden = topic!(admin, staff, "Garden budget")
    {:ok, tag} = Tags.create_tag(admin, %{"name" => unique_role_name("Garden")})

    {:ok, secret_tag} =
      Tags.create_tag(admin, %{"name" => unique_role_name("Gate"), "category_id" => staff.id})

    {:ok, read} =
      Forum.create_topic(admin, help, %{
        "title" => "Garden tools",
        "body" => "?",
        "tag_ids" => [tag.id]
      })

    :ok = Reading.mark_read(me, read)

    topics = Suggestions.suggest(me, :topic, "garden")
    assert ids(topics) == [read.id, old.id]
    refute hidden.id in ids(Suggestions.suggest(me, :topic, ""))
    assert ids(Suggestions.suggest(me, :topic, "")) == [read.id]

    assert hd(Suggestions.suggest(me, :category, "")).id == help.id
    assert ids(Suggestions.suggest(me, :category, "gen")) == [general.id]
    refute staff.id in ids(Suggestions.suggest(me, :category, ""))

    assert hd(Suggestions.suggest(me, :tag, "")).id == tag.id
    refute secret_tag.id in ids(Suggestions.suggest(me, :tag, "ga"))
  end

  @tag req: "TP-10"
  test "TP-10 + suggests only the roles the user may tag", %{admin: admin, me: me} do
    {:ok, quiet} = Access.create_role(admin, %{"name" => unique_role_name("Quiet")})
    slugs = &Enum.map(Suggestions.suggest(&1, :role, &2), fn role -> Access.role_slug(role) end)

    assert slugs.(me, "mod") == ["moderator"]
    refute Access.role_slug(quiet) in slugs.(me, "")
    assert Access.role_slug(quiet) in slugs.(user_with_role_fixture(:moderator), "quiet")
    refute "member" in slugs.(admin, "")
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InlineCardsTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Forum.Tags
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General", "description" => "Chat"})
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff room"})

    for role <- [:guest, :member],
        do:
          {:ok, _} =
            Access.set_permission(admin, Access.built_in_role!(role), staff, :view, :deny)

    starter = user_fixture(%{display_name: "Sam"})

    {:ok, topic} =
      Forum.create_topic(starter, general, %{
        "title" => "Garden plans",
        "body" => "Roses **first**"
      })

    {:ok, hidden} = Forum.create_topic(admin, staff, %{"title" => "Pay rises", "body" => "Shh"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, staff: staff, topic: topic, hidden: hidden}
  end

  defp open(user, topic) do
    conn = if user, do: log_in_user(build_conn(), user), else: build_conn()
    {:ok, lv, _html} = live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})
    lv
  end

  defp show(lv, kind, ref) do
    render_hook(lv, "show_card", %{"kind" => kind, "ref" => ref})
    lv
  end

  @tag req: "TP-10"
  test "TP-10 a #topic card previews it, opens it and follows it", %{topic: topic} do
    reader = user_fixture()
    lv = reader |> open(topic) |> show("topic", topic.id)
    assert_reply(lv, %{shown: true})

    assert has_element?(lv, "#inline-card-name", "Garden plans")
    assert has_element?(lv, "#inline-card", "Started by Sam")
    assert has_element?(lv, "#inline-card", "Roses first")
    assert has_element?(lv, ~s(#inline-card a[href="/t/#{topic.id}/#{topic.slug}"]), "Open topic")

    lv |> element("#inline-card button", "Follow") |> render_click()
    assert Reading.following?(reader, topic)
    lv |> element("#inline-card button", "Unfollow") |> render_click()
    refute Reading.following?(reader, topic)

    # Visitors get the preview, without Follow.
    lv = nil |> open(topic) |> show("topic", topic.id)
    refute has_element?(lv, "#inline-card button", "Follow")
  end

  @tag req: "TP-10"
  test "TP-10 what the reader may not view has no card: the link is followed instead", %{
    topic: topic,
    hidden: hidden,
    staff: staff
  } do
    lv = user_fixture() |> open(topic) |> show("topic", hidden.id)
    assert_reply(lv, %{shown: false})
    refute has_element?(lv, "#inline-card")

    show(lv, "category", staff.slug)
    assert_reply(lv, %{shown: false})

    for {kind, ref} <- [{"role", "member"}, {"user", "x"}, {"nothing", "x"}, {"tag", "none"}] do
      show(lv, kind, ref)
      assert_reply(lv, %{shown: false})
    end
  end

  @tag req: "TP-10"
  test "TP-10 a /category card lists its latest topics, with New topic for those who may", %{
    topic: topic,
    general: general
  } do
    lv = user_fixture() |> open(topic) |> show("category", general.slug)
    assert has_element?(lv, "#inline-card-name", "General")
    assert has_element?(lv, "#inline-card", "Chat")
    assert has_element?(lv, "#inline-card", "1 topic")
    assert has_element?(lv, "#inline-card li a", "Garden plans")
    assert has_element?(lv, ~s(#inline-card a[href="/c/#{general.slug}/new"]), "New topic")

    lv = nil |> open(topic) |> show("category", general.slug)
    refute has_element?(lv, "#inline-card a", "New topic")
  end

  @tag req: "TP-10"
  test "TP-10 +role and $tag cards", %{admin: admin, topic: topic, general: general} do
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Crew")})
    :ok = Access.grant_role(user_fixture(%{display_name: "Ada"}), role)

    {:ok, tag} =
      Tags.create_tag(admin, %{"name" => unique_role_name("Roses"), "category_id" => general.id})

    {:ok, _} = Forum.set_topic_tags(admin, topic, [tag.id])

    lv = user_fixture() |> open(topic) |> show("role", Access.role_slug(role))
    assert has_element?(lv, "#inline-card-name", role.name)
    assert has_element?(lv, "#inline-card", "1 member")
    assert has_element?(lv, "#inline-card li", "Ada")
    assert has_element?(lv, ~s(#inline-card a[href="/r/#{Access.role_slug(role)}"]))

    show(lv, "tag", tag.slug)
    assert has_element?(lv, "#inline-card-name", tag.name)
    assert has_element?(lv, "#inline-card", "A tag of General")
    assert has_element?(lv, "#inline-card li a", "Garden plans")
    assert has_element?(lv, "#inline-card a", "Filter by tag")
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicTypeTest do
  @moduledoc """
  Topic Type (steward request, 2026-11-07): a category's topics are "User" (as before) or
  "Topical": the opening message shows an icon chosen from those administrators upload,
  never its starter's name or avatar, and any moderator edits it and changes its icon.
  """
  use IdejoWeb.ConnCase, async: true

  import Ecto.Query
  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures
  import Phoenix.LiveViewTest

  alias Idejo.Forum
  alias Idejo.Forum.{TopicIcon, TopicIcons}
  alias Idejo.Moderation.Action
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, wiki} = Forum.create_category(admin, %{"name" => "Wiki", "topic_type" => "topical"})
    {:ok, chat} = Forum.create_category(admin, %{"name" => "Chat"})
    {:ok, star} = TopicIcons.create(admin, image_file(:png), %{"name" => "Star"})
    {:ok, moon} = TopicIcons.create(admin, image_file(:png), %{"name" => "Moon"})
    starter = user_fixture(%{display_name: "Secret Starter"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, wiki: wiki, chat: chat, star: star, moon: moon, starter: starter}
  end

  defp start(user, category, attrs),
    do:
      Forum.create_topic(user, category, Map.merge(%{"title" => "Rules", "body" => "Hi"}, attrs))

  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  test "a topical category's topic takes one of the icons and hides its starter", %{
    wiki: wiki,
    chat: chat,
    star: star,
    starter: starter
  } do
    assert {:error, changeset} = start(starter, wiki, %{})
    assert changeset.errors[:icon_id]
    assert {:error, _} = start(starter, wiki, %{"icon_id" => Ecto.UUID.generate()})

    {:ok, topic} = start(starter, wiki, %{"icon_id" => star.id})
    assert topic.topical
    assert topic.icon_id == star.id
    [opening] = Forum.list_messages(topic)
    assert opening.anonymous
    assert Idejo.Messages.author_name(opening) == "the topic"

    # User topics stay as they were; an icon given there is ignored.
    {:ok, user_topic} = start(starter, chat, %{"icon_id" => star.id})
    refute user_topic.topical
    assert user_topic.icon_id == nil
    refute hd(Forum.list_messages(user_topic)).anonymous
  end

  test "readers see the icon, never the starter, on the opening message and in lists", %{
    conn: conn,
    wiki: wiki,
    star: star,
    starter: starter
  } do
    {:ok, topic} = start(starter, wiki, %{"icon_id" => star.id})
    [opening] = Forum.list_messages(topic)

    {:ok, reply} =
      Forum.post_message(user_fixture(%{display_name: "Replier"}), topic, %{"body" => "Yo"})

    {:ok, lv, _html} = watch(conn, topic)

    assert has_element?(
             lv,
             "#message-#{opening.id} .topic-icon img[src='#{TopicIcons.url(star)}']"
           )

    refute has_element?(lv, "#message-#{opening.id} .author-name")
    refute render(lv) =~ "Secret Starter"
    assert has_element?(lv, "#message-#{reply.id} .author-name", "Replier")

    list = conn |> get(~p"/c/#{wiki.slug}") |> html_response(200)
    refute list =~ "Secret Starter"
    assert list =~ TopicIcons.url(star)
  end

  test "moderators edit the opening message and change its icon; the author edits it too", %{
    wiki: wiki,
    star: star,
    moon: moon,
    starter: starter,
    admin: admin
  } do
    {:ok, topic} = start(starter, wiki, %{"icon_id" => star.id})
    [opening] = Forum.list_messages(topic)

    {:ok, role} = Idejo.Access.create_role(admin, %{"name" => unique_role_name("Mods")})
    {:ok, _} = Idejo.Access.set_permission(admin, role, wiki, :moderate, :allow)
    mod = user_fixture()
    {:ok, _} = Idejo.Access.assign_role(admin, mod, role)

    {:ok, lv, _html} = watch(log_in_user(build_conn(), mod), topic)
    assert has_element?(lv, "#message-#{opening.id}-edit")

    {:ok, _} = Idejo.Messages.edit_as_moderator(mod, opening, "Better rules", nil)
    assert Repo.reload!(opening).body_md == "Better rules"

    lv |> element("#message-#{opening.id}-icon") |> render_click()
    assert has_element?(lv, "#icon-picker-#{star.id}[aria-pressed='true']")
    lv |> element("#icon-picker-#{moon.id}") |> render_click()

    assert Repo.reload!(topic).icon_id == moon.id
    assert Repo.get_by!(Action, action: "topic.icon").target_id == topic.id
    refute has_element?(lv, "#icon-picker")

    assert has_element?(
             lv,
             "#message-#{opening.id} .topic-icon img[src='#{TopicIcons.url(moon)}']"
           )

    # Members who may not moderate get no button, and are refused.
    {:ok, member_lv, _html} = watch(log_in_user(build_conn(), user_fixture()), topic)
    refute has_element?(member_lv, "#message-#{opening.id}-icon")
    assert Forum.set_topic_icon(user_fixture(), topic, star) == {:error, :forbidden}

    # The starter still edits their own message.
    {:ok, starter_lv, _html} = watch(log_in_user(build_conn(), starter), topic)
    assert has_element?(starter_lv, "#message-#{opening.id}-edit")
  end

  test "the new topic form chooses the icon in a dialog", %{
    conn: conn,
    wiki: wiki,
    star: star,
    starter: starter
  } do
    {:ok, lv, _html} = live(log_in_user(conn, starter), ~p"/c/#{wiki.slug}/new")
    assert has_element?(lv, "#topic-icon")

    lv |> element("#choose-icon") |> render_click()
    assert has_element?(lv, "#icon-picker")
    lv |> element("#icon-picker-#{star.id}") |> render_click()
    refute has_element?(lv, "#icon-picker")
    assert has_element?(lv, "#topic-icon-chosen[alt='Star']")

    lv
    |> form("#new-topic-form", topic: %{title: "Guide", body: "Read me"})
    |> render_submit()

    topic = Repo.one!(from t in Idejo.Forum.Topic, where: t.title == "Guide")
    assert topic.icon_id == star.id
  end

  test "a topic waiting for approval keeps its icon", %{
    admin: admin,
    wiki: wiki,
    star: star,
    starter: starter
  } do
    {:ok, wiki} = Forum.update_category(admin, wiki, %{"new_topics" => "approval"})
    {:pending, pending} = start(starter, wiki, %{"icon_id" => star.id})
    {:ok, topic} = Forum.approve_topic(admin, pending)
    assert topic.topical
    assert topic.icon_id == star.id
  end

  test "administrators upload and delete icons, and set a category's Topic Type", %{
    conn: conn,
    admin: admin,
    chat: chat,
    star: star,
    starter: starter,
    wiki: wiki
  } do
    conn = log_in_user(conn, admin)
    {:ok, lv, _html} = live(conn, ~p"/admin/topic-icons")
    assert has_element?(lv, "#topic-icon-#{star.id}", "Star")

    lv
    |> file_input("#topic-icon-form", :image, [
      %{name: "sun.png", content: File.read!(image_file(:png)), type: "image/png"}
    ])
    |> render_upload("sun.png")

    lv |> form("#topic-icon-form", icon: %{name: "Sun"}) |> render_submit()
    assert Repo.get_by(TopicIcon, name: "Sun")

    {:ok, topic} = start(starter, wiki, %{"icon_id" => star.id})
    lv |> element("#topic-icon-#{star.id} button", "Delete") |> render_click()
    refute Repo.get(TopicIcon, star.id)
    assert Repo.reload!(topic).icon_id == nil

    {:ok, cats, _html} = live(conn, ~p"/admin/categories")
    cats |> element("#category-#{chat.id} button", "Edit") |> render_click()

    cats
    |> form("#edit-category-#{chat.id}", edit: %{topic_type: "topical"})
    |> render_submit()

    assert Repo.reload!(chat).topic_type == "topical"
    assert has_element?(cats, "#topic-type-#{chat.id}", "Topical")
  end
end

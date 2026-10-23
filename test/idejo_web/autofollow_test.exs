# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AutofollowTest do
  @moduledoc """
  Topics followed by everyone (steward decision, 2026-10-23): administrators mark them;
  every user who may view one follows it unless they unfollow it, members who join later
  included, and visitors see it followed.
  """
  use IdejoWeb.ConnCase, async: true

  import Ecto.Query
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Notifications.Notification
  alias Idejo.Reading
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, news} = Forum.create_category(admin, %{"name" => "News"})
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff"})

    for role <- [:guest, :member],
        do:
          {:ok, _} =
            Access.set_permission(admin, Access.built_in_role!(role), staff, :view, :deny)

    {:ok, topic} = Forum.create_topic(admin, news, %{"title" => "Welcome", "body" => "Hello"})
    {:ok, hidden} = Forum.create_topic(admin, staff, %{"title" => "Staff only", "body" => "Hi"})
    %{admin: admin, topic: topic, hidden: hidden}
  end

  defp ids(topics), do: Enum.map(topics, & &1.id)

  test "only administrators mark a topic followed by everyone, audited", %{
    admin: admin,
    topic: topic
  } do
    assert Forum.set_autofollow(user_with_role_fixture(:moderator), topic, true) ==
             {:error, :forbidden}

    {:ok, topic} = Forum.set_autofollow(admin, topic, true)
    assert topic.autofollow

    entry = Enum.find(Audit.list_entries(), &(&1.change == "topic.autofollow"))
    assert {entry.before["autofollow"], entry.after["autofollow"]} == {false, true}

    {:ok, topic} = Forum.set_autofollow(admin, topic, false)
    refute topic.autofollow
  end

  test "everyone follows it, members who join later too, until they unfollow it", %{
    admin: admin,
    topic: topic,
    hidden: hidden
  } do
    early = user_fixture()
    {:ok, topic} = Forum.set_autofollow(admin, topic, true)
    {:ok, hidden} = Forum.set_autofollow(admin, hidden, true)
    late = user_fixture()

    for user <- [early, late] do
      assert Reading.following?(user, topic)
      assert topic.id in ids(Reading.list_followed_topics(user))
      # Not one they may not view.
      refute hidden.id in ids(Reading.list_followed_topics(user))
    end

    :ok = Reading.unfollow(late, topic)
    refute Reading.following?(late, topic)
    refute topic.id in ids(Reading.list_followed_topics(late))

    :ok = Reading.follow(late, topic)
    assert Reading.following?(late, topic)

    # Visitors see it followed, and not the one they may not view.
    assert ids(Reading.list_followed_topics(nil)) == [topic.id]
  end

  test "its new messages notify everyone who may view it and did not unfollow it", %{
    admin: admin,
    topic: topic
  } do
    {:ok, topic} = Forum.set_autofollow(admin, topic, true)
    reader = user_fixture()
    leaver = user_fixture()
    :ok = Reading.unfollow(leaver, topic)
    author = user_fixture()

    {:ok, message} = Forum.post_message(author, topic, %{"body" => "News!"})

    notified =
      Repo.all(
        from n in Notification, where: n.message_id == ^message.id, select: {n.user_id, n.kind}
      )
      |> Map.new()

    assert notified[reader.id] == "follow"
    assert notified[admin.id] == "follow"
    refute Map.has_key?(notified, leaver.id)
    refute Map.has_key?(notified, author.id)
  end

  test "Unread lists it under Following", %{admin: admin, topic: topic} do
    reader =
      user_fixture()
      |> Ecto.Changeset.change(created_at: DateTime.add(DateTime.utc_now(:second), -3600))
      |> Repo.update!()

    {:ok, _} = Forum.set_autofollow(admin, topic, true)
    {:ok, _} = Forum.post_message(user_fixture(), topic, %{"body" => "News!"})

    # The opening message and the new one.
    assert [{followed, 2}] = Reading.list_unread_followed_topics(reader)
    assert followed.id == topic.id
  end

  test "the topic page: a badge for all, the switch for administrators only", %{
    admin: admin,
    topic: topic
  } do
    path = ~p"/t/#{topic.id}/#{topic.slug}"
    member = log_in_user(build_conn(), user_fixture())
    refute member |> get(path) |> html_response(200) =~ "autofollow-form"

    conn = post(member, ~p"/t/#{topic.id}/autofollow", %{"autofollow" => "true"})
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Only administrators"
    refute Repo.reload!(topic).autofollow

    admin_conn = log_in_user(build_conn(), admin)
    assert admin_conn |> get(path) |> html_response(200) =~ "Make everyone follow it"

    conn = post(admin_conn, ~p"/t/#{topic.id}/autofollow", %{"autofollow" => "true"})
    assert redirected_to(conn) == path
    assert Repo.reload!(topic).autofollow

    page = admin_conn |> get(path) |> html_response(200)
    assert page =~ ~s(id="topic-autofollow")
    assert page =~ "Stop making everyone follow it"
    assert member |> get(path) |> html_response(200) =~ "Followed by everyone"
  end

  test "a visitor's sidebar lists it, with nothing to follow or unfollow", %{
    admin: admin,
    topic: topic
  } do
    {:ok, _} = Forum.set_autofollow(admin, topic, true)

    item =
      build_conn()
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s(#sidebar .sidebar-topic[data-topic-id="#{topic.id}"]))

    assert Enum.count(item) == 1
    assert item |> LazyHTML.query("form") |> Enum.count() == 0
  end
end

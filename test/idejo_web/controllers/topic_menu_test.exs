# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The topic menu (steward decision, 2026-10-23): no requirement ID.
defmodule IdejoWeb.TopicMenuTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Reading
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()
    {:ok, topic} = Forum.create_topic(starter, general, %{"title" => "Plans", "body" => "Hi"})
    %{starter: starter, topic: topic}
  end

  defp doc(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp query(doc, selector), do: LazyHTML.query(doc, selector)

  test "topics in lists and the sidebar open the menu; it has every item, hidden", %{
    starter: starter,
    topic: topic
  } do
    doc = doc(log_in_user(build_conn(), starter), ~p"/c/general")
    path = "/t/#{topic.id}/#{topic.slug}"

    assert [^path] =
             doc |> query("#topics li[data-topic-menu]") |> LazyHTML.attribute("data-topic-path")

    # The starter follows it: the sidebar says so, for the menu's Unfollow.
    assert Enum.count(query(doc, "#sidebar li[data-topic-menu][data-following]")) == 1

    menu = query(doc, "#topic-menu.popup-menu[role=menu][hidden]")
    assert Enum.count(menu) == 1
    text = LazyHTML.text(menu)

    for item <- ["Unfollow", "Follow", "Unfollow & mute", "Mark unread", "Copy link"],
        do: assert(text =~ item)

    assert Enum.count(query(doc, "#topic-menu [role=menuitem]")) == 5
    # So is the account menu.
    assert Enum.count(query(doc, "#account-menu .account-panel.popup-menu")) == 1

    # Visitors get no menu (the rows' data then does nothing).
    visitor = doc(build_conn(), ~p"/c/general")
    assert Enum.empty?(query(visitor, "#topic-menu"))
  end

  test "Unfollow & mute and Mark unread post back to the page", %{starter: starter, topic: topic} do
    conn = log_in_user(build_conn(), starter)
    other = user_fixture()
    {:ok, _} = Forum.post_message(other, topic, %{"body" => "Hello"})
    Reading.mark_read(starter, topic)

    back = conn |> put_req_header("referer", "http://www.example.com/c/general")

    res = post(back, ~p"/t/#{topic.id}/unread", %{"return" => "back"})
    assert redirected_to(res) == "/c/general"
    assert Phoenix.Flash.get(res.assigns.flash, :info) == "Marked unread."
    assert Reading.unread_counts(starter, [topic.id]) == %{topic.id => 1}

    res = post(back, ~p"/t/#{topic.id}/mute", %{"return" => "back"})
    assert redirected_to(res) == "/c/general"
    refute Reading.following?(starter, topic)
    assert Repo.get_by!(Idejo.Reading.Follow, user_id: starter.id, topic_id: topic.id).muted

    # Follow lifts it.
    post(back, ~p"/t/#{topic.id}/follow", %{"return" => "back"})
    refute Repo.get_by!(Idejo.Reading.Follow, user_id: starter.id, topic_id: topic.id).muted
  end

  test "menus are see-through and blurred, from the server stylesheet" do
    css = File.read!("assets/css/app.css")
    assert css =~ "var(--menu-opacity, 70%)"
    assert css =~ "blur(var(--menu-blur, 4px))"

    default = Idejo.Settings.default(:custom_css)
    assert default =~ "--menu-opacity: 70%;"
    assert default =~ "--menu-blur: 4px;"
    assert default =~ ".popup-menu {"
  end
end

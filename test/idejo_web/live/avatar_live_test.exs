# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AvatarLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Accounts
  alias Idejo.Forum
  alias Idejo.Uploads

  setup %{conn: conn} do
    user = user_fixture(%{display_name: "Ada"})
    %{conn: log_in_user(conn, user), user: user}
  end

  @tag req: "AC-04"
  test "AC-04 a user sets and removes their avatar from the profile page", %{
    conn: conn,
    user: user
  } do
    {:ok, lv, html} = live(conn, ~p"/users/settings")
    assert html =~ "Avatar"
    refute has_element?(lv, "#remove-avatar")

    path = image_file(:png)

    input =
      file_input(lv, "#avatar-form", :avatar, [
        %{name: "me.png", content: File.read!(path), type: "image/png"}
      ])

    assert {:error, {:redirect, %{to: "/users/settings"}}} = render_upload(input, "me.png")

    user = Accounts.get_user!(user.id)
    assert user.avatar_id

    {:ok, lv, html} = live(conn, ~p"/users/settings")
    assert html =~ ~s(src="#{Uploads.avatar_url(user)}")

    assert {:error, {:redirect, %{to: "/users/settings"}}} =
             lv |> element("#remove-avatar") |> render_click()

    assert Accounts.get_user!(user.id).avatar_id == nil
  end

  @tag req: "AC-04"
  test "AC-04 the avatar shows above the user's messages and on their card", %{user: user} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, user} = Accounts.set_avatar(user, image_file(:png))
    {:ok, topic} = Forum.create_topic(user, general, %{"title" => "Hello", "body" => "Hi"})
    [message] = Forum.list_messages(topic)
    url = Uploads.avatar_url(user)

    page = build_conn() |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)
    doc = LazyHTML.from_document(page)

    assert doc
           |> LazyHTML.query(~s(#message-#{message.id}-author img[src="#{url}"][alt=""]))
           |> Enum.count() == 1

    card = build_conn() |> get(~p"/u/#{user.id}") |> html_response(200)
    assert card =~ ~s(src="#{url}")

    # Without one, the initial.
    other = user_fixture(%{display_name: "bo"})
    card = build_conn() |> get(~p"/u/#{other.id}") |> html_response(200)

    assert card
           |> LazyHTML.from_document()
           |> LazyHTML.query(".avatar-placeholder")
           |> LazyHTML.text() =~ "B"
  end
end

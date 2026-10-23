# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.DarkAvatarTest do
  @moduledoc """
  A second avatar for the dark theme (steward decision, 2026-10-23): optional, set and
  removed in Profile and account, shown instead of the avatar with the dark theme.
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Accounts
  alias Idejo.Repo
  alias Idejo.Uploads
  alias Idejo.Uploads.Upload
  alias IdejoWeb.UserComponents

  setup %{conn: conn} do
    user = user_fixture(%{display_name: "Ada"})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp path_of(url), do: url |> String.replace_prefix("/uploads/", "") |> Uploads.get_by_name()

  defp avatar_html(user),
    do: rendered_to_string(UserComponents.avatar(%{user: user, size: :small, __changed__: nil}))

  test "the dark picture is set, replaced and removed apart from the avatar", %{user: user} do
    {:ok, user} = Accounts.set_avatar(user, image_file(:png))
    {:ok, user} = Accounts.set_avatar(user, image_file(:png), :dark)
    assert user.avatar_dark_id
    assert Uploads.dark_avatar_url(user) == "/uploads/#{user.avatar_dark_id}.webp"
    {_upload, old_path} = path_of(Uploads.dark_avatar_url(user))

    {:ok, user} = Accounts.set_avatar(user, image_file(:gif), :dark)
    refute File.exists?(old_path)
    assert Repo.aggregate(Upload, :count) == 2

    {:ok, user} = Accounts.remove_avatar(user, :dark)
    assert user.avatar_dark_id == nil
    assert user.avatar_id
    assert Repo.aggregate(Upload, :count) == 1
    assert {:ok, ^user} = Accounts.remove_avatar(user, :dark)
  end

  test "deleting the account deletes both pictures", %{user: user} do
    {:ok, user} = Accounts.set_avatar(user, image_file(:png))
    {:ok, user} = Accounts.set_avatar(user, image_file(:png), :dark)

    {:ok, {deleted, _}} = Accounts.delete_user(user, valid_user_password())
    assert {deleted.avatar_id, deleted.avatar_dark_id} == {nil, nil}
    assert Repo.aggregate(Upload, :count) == 0
  end

  test "with both pictures the avatar holds both, the theme picks; with one, it shows always",
       %{user: user} do
    {:ok, user} = Accounts.set_avatar(user, image_file(:png))
    html = avatar_html(user)
    refute html =~ "avatar-has-dark"
    assert html =~ ~s(src="#{Uploads.avatar_url(user)}")

    {:ok, user} = Accounts.set_avatar(user, image_file(:png), :dark)
    doc = user |> avatar_html() |> LazyHTML.from_fragment()
    assert doc |> LazyHTML.query(".avatar.avatar-has-dark") |> Enum.count() == 1

    assert doc
           |> LazyHTML.query(
             ~s(img.avatar-light[loading="lazy"][src="#{Uploads.avatar_url(user)}"])
           )
           |> Enum.count() == 1

    assert doc
           |> LazyHTML.query(
             ~s(img.avatar-dark[loading="lazy"][src="#{Uploads.dark_avatar_url(user)}"])
           )
           |> Enum.count() == 1

    # A dark picture alone shows with both themes.
    {:ok, user} = Accounts.remove_avatar(user)
    html = avatar_html(user)
    refute html =~ "avatar-has-dark"
    assert html =~ ~s(src="#{Uploads.dark_avatar_url(user)}")

    css = File.read!("assets/css/app.css")
    assert css =~ ~s([data-theme="dark"] .avatar-has-dark {)
    assert css =~ ":root:not([data-theme]) .avatar-has-dark {"
  end

  test "Profile and account: the dark picture is folded away until set, then shown open", %{
    conn: conn,
    user: user
  } do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    assert has_element?(lv, "details#dark-avatar:not([open])", "Dark mode picture")
    refute has_element?(lv, "#remove-dark-avatar")

    input =
      file_input(lv, "#dark-avatar-form", :dark_avatar, [
        %{name: "night.png", content: File.read!(image_file(:png)), type: "image/png"}
      ])

    assert {:error, {:redirect, %{to: "/users/settings"}}} = render_upload(input, "night.png")
    user = Accounts.get_user!(user.id)
    assert user.avatar_dark_id
    assert user.avatar_id == nil

    {:ok, lv, _html} = live(conn, ~p"/users/settings")
    assert has_element?(lv, "details#dark-avatar[open]")

    assert {:error, {:redirect, %{to: "/users/settings"}}} =
             lv |> element("#remove-dark-avatar") |> render_click()

    assert Accounts.get_user!(user.id).avatar_dark_id == nil
  end
end

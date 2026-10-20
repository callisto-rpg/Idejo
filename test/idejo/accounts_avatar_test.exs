# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccountsAvatarTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Accounts
  alias Idejo.Federation.Activity
  alias Idejo.Uploads
  alias Idejo.Uploads.Upload

  setup do
    %{user: user_fixture()}
  end

  defp file_of(user),
    do:
      user
      |> Uploads.avatar_url()
      |> String.replace_prefix("/uploads/", "")
      |> Uploads.get_by_name()

  @tag req: "AC-04"
  test "AC-04 an avatar is a 256 px WebP square without metadata", %{user: user} do
    assert Uploads.avatar_url(user) == nil
    {:ok, user} = Accounts.set_avatar(user, image_file(:jpg, width: 400, height: 300))

    assert Uploads.avatar_url(user) == "/uploads/#{user.avatar_id}.webp"
    {upload, path} = file_of(user)
    assert upload.mime == "image/webp"
    assert upload.user_id == user.id

    {:ok, stored} = Image.open(path)
    assert {Image.width(stored), Image.height(stored)} == {256, 256}
    refute File.read!(path) =~ "Secret Person"

    assert [%Activity{payload: %{"icon" => icon}}] =
             Repo.all(from a in Activity, where: a.object_uri == ^user.uri and a.verb == "update")

    assert icon == Uploads.avatar_url(user)
  end

  @tag req: "AC-04"
  test "AC-04 a new avatar replaces the old one, file and all; it can be removed", %{user: user} do
    {:ok, user} = Accounts.set_avatar(user, image_file(:png))
    {_old, old_path} = file_of(user)

    {:ok, user} = Accounts.set_avatar(user, image_file(:gif))
    refute File.exists?(old_path)
    assert Repo.aggregate(Upload, :count) == 1

    {_new, new_path} = file_of(user)
    {:ok, user} = Accounts.remove_avatar(user)
    assert user.avatar_id == nil
    refute File.exists?(new_path)
    assert Repo.aggregate(Upload, :count) == 0
    assert {:ok, ^user} = Accounts.remove_avatar(user)
  end

  @tag req: "AC-04"
  test "AC-04 a file that is not an image leaves the avatar as it was", %{user: user} do
    {:ok, user} = Accounts.set_avatar(user, image_file(:png))
    assert Accounts.set_avatar(user, raw_file("me.png", "nope")) == {:error, :not_an_image}
    assert Repo.reload!(user).avatar_id == user.avatar_id
  end

  @tag req: "AC-07"
  test "AC-07 deleting the account deletes its avatar", %{user: user} do
    {:ok, user} = Accounts.set_avatar(user, image_file(:png))
    {_upload, path} = file_of(user)

    {:ok, {deleted, _}} = Accounts.delete_user(user, valid_user_password())
    assert deleted.avatar_id == nil
    refute File.exists?(path)
    assert Repo.aggregate(Upload, :count) == 0
  end
end

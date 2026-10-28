# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.UploadsCleanupTest do
  # Writes settings, which every test shares.
  use Idejo.DataCase, async: false
  use Oban.Testing, repo: Idejo.Repo

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Settings
  alias Idejo.Uploads
  alias Idejo.Uploads.Upload

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    %{admin: admin, user: user_fixture(), general: general}
  end

  defp image!(user) do
    {:ok, upload} = Uploads.store_image(user, image_file(:png))
    upload
  end

  defp markdown(upload), do: "Look: ![photo](#{Uploads.url(upload)})"

  # Two days old: past the day an unsent text keeps its images.
  defp age!(upload_id) do
    Repo.update_all(from(u in Upload, where: u.id == ^upload_id),
      set: [created_at: DateTime.add(DateTime.utc_now(), -2, :day)]
    )
  end

  defp file(upload), do: Path.join(Application.fetch_env!(:idejo, :uploads_dir), upload.path)

  @tag req: "TP-12"
  test "TP-12 uploads nothing uses are deleted with their files, after a day", %{
    admin: admin,
    user: user,
    general: general
  } do
    unused = image!(user)
    recent = image!(user)
    in_message = image!(user)
    in_version = image!(user)
    in_deleted = image!(user)
    in_setting = image!(user)
    in_bio = image!(user)

    {:ok, topic} =
      Forum.create_topic(user, general, %{"title" => "Photos", "body" => markdown(in_message)})

    # Edited away, the image stays in the earlier version (GM-11).
    {:ok, edited} = Forum.post_message(user, topic, %{"body" => markdown(in_version)})
    {:ok, _} = Messages.edit(user, edited, "No photo after all")

    # Moderators still read a deleted message (MO-02).
    {:ok, gone} = Forum.post_message(user, topic, %{"body" => markdown(in_deleted)})
    {:ok, _} = Messages.delete_as_moderator(admin, gone)

    {:ok, _} = Settings.update_settings(admin, %{"server_rules" => markdown(in_setting)})

    # AC-04: a bio shows an image by its address.
    {:ok, _} = Idejo.Accounts.update_user_bio(user, %{"bio_md" => markdown(in_bio)})

    {:ok, user} = Idejo.Accounts.set_avatar(user, image_file(:png))
    {:ok, user} = Idejo.Accounts.set_avatar(user, image_file(:png), :dark)

    ids =
      [unused, in_message, in_version, in_deleted, in_setting, in_bio]
      |> Enum.map(& &1.id)
      |> Kernel.++([user.avatar_id, user.avatar_dark_id])

    Enum.each(ids, &age!/1)

    assert perform_job(Uploads.CleanupWorker, %{}) == :ok

    assert Repo.get(Upload, unused.id) == nil
    refute File.exists?(file(unused))

    for kept <- [recent, in_message, in_version, in_deleted, in_setting, in_bio] do
      assert Repo.get(Upload, kept.id), "#{kept.path} was deleted"
      assert File.exists?(file(kept))
    end

    assert Repo.get(Upload, user.avatar_id)
    assert Repo.get(Upload, user.avatar_dark_id)
    assert Uploads.delete_unused() == []
  end

  @tag req: "TP-12"
  test "TP-12 the clean-up runs every night at 04:00, after the backup" do
    crontab =
      Application.fetch_env!(:idejo, Oban)[:plugins]
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> opts[:crontab]
        _ -> nil
      end)

    assert {"0 4 * * *", Uploads.CleanupWorker} in crontab
  end
end

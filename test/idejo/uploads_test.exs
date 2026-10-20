# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.UploadsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Settings
  alias Idejo.Uploads

  setup do
    %{user: user_fixture(), admin: user_with_role_fixture(:administrator)}
  end

  defp stored_path(upload), do: upload.path |> Uploads.get_by_name() |> elem(1)

  @tag req: "TP-12"
  test "TP-12 an image is re-encoded in its format and stored on local disk", %{user: user} do
    for {format, mime} <- [
          jpg: "image/jpeg",
          png: "image/png",
          gif: "image/gif",
          webp: "image/webp"
        ] do
      assert {:ok, upload} = Uploads.store_image(user, image_file(format))
      assert upload.mime == mime
      assert upload.path =~ ~r/\A[0-9a-f-]{36}\.#{format}\z/
      assert upload.user_id == user.id
      assert Uploads.url(upload) == "/uploads/" <> upload.path
      assert File.stat!(stored_path(upload)).size == upload.size
    end
  end

  @tag req: "SP-05"
  test "SP-05 image metadata is stripped on upload", %{user: user} do
    original = image_file(:jpg)
    assert File.read!(original) =~ "Secret Person"

    {:ok, upload} = Uploads.store_image(user, original)
    refute File.read!(stored_path(upload)) =~ "Secret Person"
  end

  @tag req: "TP-12"
  test "TP-12 only real images are taken, whatever their name", %{user: user} do
    assert Uploads.store_image(user, raw_file("photo.png", "not an image")) ==
             {:error, :not_an_image}

    assert Uploads.store_image(user, raw_file("empty.jpg", "")) == {:error, :not_an_image}

    svg =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><script>x</script></svg>)

    assert Uploads.store_image(user, raw_file("drawing.png", svg)) == {:error, :not_an_image}
  end

  @tag req: "TP-12"
  test "TP-12 one server-wide size limit, set by administrators", %{user: user, admin: admin} do
    assert Settings.get(:upload_max_mb) == 3
    assert Uploads.max_bytes() == 3_000_000

    {:ok, _} = Settings.update_settings(admin, %{"upload_max_mb" => "1"})
    big = raw_file("big.jpg", :binary.copy(<<0>>, 1_000_001))
    assert Uploads.store_image(user, big) == {:error, :too_large}
  end

  @tag req: "TP-12"
  test "TP-12 an image with too many pixels is refused", %{user: user} do
    path = image_file(:png, width: 8_000, height: 6_000)
    assert Uploads.store_image(user, path) == {:error, :too_many_pixels}
  end
end

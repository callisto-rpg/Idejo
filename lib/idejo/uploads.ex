# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Uploads do
  @moduledoc """
  Uploaded images (TP-12, MVP: images only, one server-wide size limit, local disk).

  Every upload is opened with libvips (`Image`), which decides what it is from its content,
  never from its name: only JPEG, PNG, GIF and WebP are taken. It is then re-encoded in the
  same format, turned upright and written without its metadata (SP-05: no EXIF, GPS or
  comments leave the uploader's file), as `<id>.<ext>` in the uploads directory
  (`:uploads_dir`). The size limit is the `upload_max_mb` setting; images over 40 megapixels
  are refused, so a small file cannot unpack into a huge one.

  Files are served at `/uploads/<id>.<ext>` to anyone with the link (steward decision).

  Avatars (AC-04) pass the same checks, then become a 256 px square cropped from the centre,
  always WebP, so a user's avatar is at `/uploads/<avatar_id>.webp` (`avatar_url/1`) without
  loading its upload.
  """
  import Ecto.Query, warn: false

  alias Idejo.Accounts.User
  alias Idejo.RateLimit
  alias Idejo.Repo
  alias Idejo.Settings
  alias Idejo.Uploads.Upload
  alias Vix.Vips.Image, as: VipsImage

  # libvips loader => {extension, MIME type}
  @formats %{
    "jpegload" => {"jpg", "image/jpeg"},
    "pngload" => {"png", "image/png"},
    "gifload" => {"gif", "image/gif"},
    "webpload" => {"webp", "image/webp"}
  }

  @max_pixels 40_000_000

  @doc "The accepted file name extensions, for upload pickers."
  @spec extensions() :: [String.t()]
  def extensions, do: ~w(.jpg .jpeg .png .gif .webp)

  @doc "The size limit in bytes (`upload_max_mb` setting)."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: Settings.get(:upload_max_mb) * 1_000_000

  @doc """
  Stores the image at `path`, uploaded by `user`: checked, re-encoded without metadata and
  saved. Returns the new upload, or why it was refused.
  """
  @spec store_image(User.t(), Path.t()) ::
          {:ok, Upload.t()}
          | {:error, :too_large | :not_an_image | :too_many_pixels | :rate_limited}
  def store_image(%User{} = user, path) do
    with :ok <- check_size(path),
         :ok <- RateLimit.check(:upload, user.id),
         {:ok, image, format} <- open(path, -1),
         :ok <- check_pixels(image) do
      save(user, image, format)
    end
  end

  @avatar_size 256

  @doc """
  Stores the image at `path` as `user`'s avatar picture (AC-04): checked like any image, then
  a #{@avatar_size} px WebP square without metadata. Only the first frame of an animation.
  """
  @spec store_avatar(User.t(), Path.t()) ::
          {:ok, Upload.t()}
          | {:error, :too_large | :not_an_image | :too_many_pixels | :rate_limited}
  def store_avatar(%User{} = user, path) do
    with :ok <- check_size(path),
         :ok <- RateLimit.check(:upload, user.id),
         {:ok, image, {ext, _mime}} <- open(path, 1),
         :ok <- check_pixels(image),
         image = if(ext == "jpg", do: Image.autorotate!(image), else: image),
         {:ok, square} <- Image.thumbnail(image, @avatar_size, crop: :center) do
      save(user, square, {"webp", "image/webp"})
    else
      {:error, reason}
      when reason in [:too_large, :not_an_image, :too_many_pixels, :rate_limited] ->
        {:error, reason}

      _ ->
        {:error, :not_an_image}
    end
  end

  @doc "The public path of a user's avatar, or `nil` when they have none (AC-04)."
  @spec avatar_url(User.t()) :: String.t() | nil
  def avatar_url(%User{avatar_id: nil}), do: nil
  def avatar_url(%User{avatar_id: id}), do: "/uploads/#{id}.webp"

  @doc """
  The public path of a user's avatar for the dark theme, or `nil` when they have none
  (steward decision, 2026-10-23).
  """
  @spec dark_avatar_url(User.t()) :: String.t() | nil
  def dark_avatar_url(%User{avatar_dark_id: nil}), do: nil
  def dark_avatar_url(%User{avatar_dark_id: id}), do: "/uploads/#{id}.webp"

  @doc "Deletes an upload and its file, e.g. a replaced avatar. Unknown ids do nothing."
  @spec delete(Ecto.UUID.t() | nil) :: :ok
  def delete(nil), do: :ok

  def delete(id) do
    case Repo.get(Upload, id) do
      nil ->
        :ok

      upload ->
        Repo.delete!(upload)
        remove_file(upload.path)
    end
  end

  # The name is one this module made (`<uuid>.<ext>`), read back from the database.
  # sobelow_skip ["Traversal.FileModule"]
  defp remove_file(name) do
    File.rm(Path.join(dir(), name))
    :ok
  end

  defp check_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= 0 -> {:error, :not_an_image}
      {:ok, %{size: size}} -> if size <= max_bytes(), do: :ok, else: {:error, :too_large}
      _ -> {:error, :not_an_image}
    end
  end

  # `pages: -1` keeps every frame, so an animated GIF or WebP keeps moving; the loader names
  # the real format.
  defp open(path, pages) do
    with {:ok, image} <- Image.open(path, pages: pages, fail_on: :error),
         {:ok, loader} <- VipsImage.header_value(image, "vips-loader"),
         {_ext, _mime} = format <- Map.get(@formats, loader) do
      {:ok, image, format}
    else
      _ -> {:error, :not_an_image}
    end
  end

  defp check_pixels(image) do
    if Image.width(image) * Image.height(image) <= @max_pixels,
      do: :ok,
      else: {:error, :too_many_pixels}
  end

  # The path is the configured directory and a name made here from a new UUID: nothing from
  # the uploader reaches it.
  # sobelow_skip ["Traversal.FileModule"]
  defp save(user, image, {ext, mime}) do
    id = Ecto.UUID.generate(version: 7)
    name = "#{id}.#{ext}"
    dest = Path.join(dir(), name)
    File.mkdir_p!(dir())

    upright = if ext == "jpg", do: Image.autorotate!(image), else: image

    with {:ok, _} <- Image.write(upright, dest, strip_metadata: true),
         {:ok, %{size: size}} <- File.stat(dest) do
      Repo.insert(%Upload{id: id, user_id: user.id, path: name, mime: mime, size: size})
    else
      _ ->
        File.rm(dest)
        {:error, :not_an_image}
    end
  end

  @doc "The public path of an upload, as written in Markdown."
  @spec url(Upload.t()) :: String.t()
  def url(%Upload{path: path}), do: "/uploads/" <> path

  @doc """
  Finds an upload by its file name (`<id>.<ext>`), with the path of its file, or `nil`.
  """
  @spec get_by_name(String.t()) :: {Upload.t(), Path.t()} | nil
  def get_by_name(name) when is_binary(name) do
    with true <- Regex.match?(~r/\A[0-9a-f-]{36}\.(jpg|png|gif|webp)\z/, name),
         %Upload{} = upload <- Repo.get_by(Upload, path: name) do
      {upload, Path.join(dir(), upload.path)}
    else
      _ -> nil
    end
  end

  defp dir, do: Application.fetch_env!(:idejo, :uploads_dir)
end

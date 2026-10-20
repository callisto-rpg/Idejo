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
  """
  import Ecto.Query, warn: false

  alias Idejo.Accounts.User
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
          {:ok, Upload.t()} | {:error, :too_large | :not_an_image | :too_many_pixels}
  def store_image(%User{} = user, path) do
    with :ok <- check_size(path),
         {:ok, image, format} <- open(path),
         :ok <- check_pixels(image) do
      save(user, image, format)
    end
  end

  defp check_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= 0 -> {:error, :not_an_image}
      {:ok, %{size: size}} -> if size <= max_bytes(), do: :ok, else: {:error, :too_large}
      _ -> {:error, :not_an_image}
    end
  end

  # All frames, so an animated GIF or WebP keeps moving; the loader names the real format.
  defp open(path) do
    with {:ok, image} <- Image.open(path, pages: -1, fail_on: :error),
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

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ImageFixtures do
  @moduledoc """
  Image files for upload tests (TP-12), made with libvips in a scratch directory.
  """

  alias Vix.Vips.Image, as: VipsImage
  alias Vix.Vips.MutableImage

  @doc """
  Writes a small image in `format` (`:jpg`, `:png`, `:gif`, `:webp`) and returns its path.
  A JPEG carries an EXIF artist, "Secret Person", for metadata tests.
  """
  def image_file(format \\ :jpg, opts \\ []) do
    width = Keyword.get(opts, :width, 40)
    height = Keyword.get(opts, :height, 30)
    {:ok, image} = Image.new(width, height, color: :red)

    image =
      if format == :jpg do
        {:ok, image} =
          VipsImage.mutate(image, fn m ->
            MutableImage.set(m, "exif-ifd0-Artist", :gchararray, "Secret Person")
          end)

        image
      else
        image
      end

    path = scratch("#{System.unique_integer([:positive])}.#{format}")
    Image.write!(image, path)
    path
  end

  @doc "Writes `content` to a scratch file named `name` and returns its path."
  def raw_file(name, content) do
    path = scratch("#{System.unique_integer([:positive])}-#{name}")
    File.write!(path, content)
    path
  end

  defp scratch(name) do
    dir = Path.join(System.tmp_dir!(), "idejo-image-fixtures")
    File.mkdir_p!(dir)
    Path.join(dir, name)
  end
end

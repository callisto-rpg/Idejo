# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.UploadController do
  @moduledoc """
  Images (TP-12, SP-05, AP-12): the same types, size limit and metadata stripping as the
  web (`Uploads.store_image/2`). Answers the Markdown the web composer inserts.
  """
  use IdejoWeb.Api.Controller

  alias Idejo.Uploads

  def create(conn, %{"image" => %Plug.Upload{path: path, filename: filename}}) do
    with {:ok, upload} <- Uploads.store_image(user(conn), path) do
      json(conn, %{
        "upload_id" => upload.id,
        "url" => Api.absolute(Uploads.url(upload)),
        "markdown" => IdejoWeb.ImageUploads.markdown(filename, upload),
        "width" => upload.width,
        "height" => upload.height
      })
    end
  end

  def create(_conn, _params), do: {:error, :bad_request}
end

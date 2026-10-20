# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UploadController do
  @moduledoc """
  Serves uploaded images at `/uploads/<id>.<ext>` (TP-12): to anyone with the link (steward
  decision), without a session. The type comes from the stored upload, never from the
  request; the file cannot be read as anything but that image (`nosniff`, a policy that
  allows nothing to run), and it never changes, so it may be cached for good.
  """
  use IdejoWeb, :controller

  alias Idejo.Uploads

  # The path comes from a stored upload, found by a name that must be `<uuid>.<ext>`
  # (`Uploads.get_by_name/1`), never from the request itself.
  # sobelow_skip ["Traversal.SendFile"]
  def show(conn, %{"name" => name}) do
    case Uploads.get_by_name(name) do
      nil ->
        conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not found")

      {upload, path} ->
        conn
        |> put_resp_header("content-type", upload.mime)
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_file(200, path)
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ImageUploads do
  @moduledoc """
  Images in messages (TP-12) for the LiveViews that write them: the composer and the message
  editor. An image pasted or dropped into the text (steward decision; the `Composer` and
  `EditorImages` hooks call `upload/2`), or picked with the editor's "Add image" button,
  uploads at once. When it is stored (`Idejo.Uploads.store_image/2`) the page gets
  `"image_uploaded"` with its upload name and Markdown, which the hook inserts at the caret,
  as unsent text: nothing is posted until the author sends it. The composer itself gets no
  button (GM-07).
  """
  use Gettext, backend: IdejoWeb.Gettext

  import Phoenix.Component, only: [assign: 3, upload_errors: 2]
  import Phoenix.LiveView

  alias Idejo.Uploads

  @doc """
  Allows image uploads under `name`, for a user allowed to post: `allowed?` false leaves
  them off.
  """
  @spec allow(Phoenix.LiveView.Socket.t(), atom(), boolean()) :: Phoenix.LiveView.Socket.t()
  def allow(socket, name, allowed? \\ true)
  def allow(socket, _name, false), do: assign(socket, :image_error, nil)

  def allow(socket, name, true) do
    socket
    |> assign(:image_error, nil)
    |> allow_upload(name,
      accept: Uploads.extensions(),
      max_entries: 1,
      max_file_size: Uploads.max_bytes(),
      auto_upload: true,
      progress: &progress/3
    )
  end

  @doc """
  Turns refused entries (wrong type, too large) into a message and drops them. Call from the
  form's `phx-change` handler.
  """
  @spec check(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  def check(socket, name) do
    case socket.assigns[:uploads] && socket.assigns.uploads[name] do
      nil ->
        socket

      config ->
        Enum.reduce(config.entries, socket, &refuse_invalid(&2, name, config, &1))
    end
  end

  defp refuse_invalid(socket, name, config, entry) do
    case upload_errors(config, entry) do
      [] ->
        socket

      [error | _] ->
        socket |> cancel_upload(name, entry.ref) |> assign(:image_error, message(error))
    end
  end

  # A poster who lost the right since mount (TopicLive's `can_post?`) stores nothing.
  defp progress(name, entry, %{assigns: %{can_post?: false}} = socket) do
    if entry.done?, do: consume_uploaded_entry(socket, entry, fn _ -> {:ok, nil} end)

    {:noreply,
     socket |> cancel_upload(name, entry.ref) |> assign(:image_error, message(:forbidden))}
  end

  defp progress(name, entry, socket) do
    if entry.done? do
      user = socket.assigns.current_scope.user

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Uploads.store_image(user, path)}
        end)

      case result do
        {:ok, upload} ->
          markdown = "![#{alt(entry.client_name)}](#{Uploads.url(upload)})"

          {:noreply,
           socket
           |> assign(:image_error, nil)
           |> push_event("image_uploaded", %{upload: name, markdown: markdown})}

        {:error, reason} ->
          {:noreply, assign(socket, :image_error, message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  # The file's name, without its extension or Markdown brackets, is the first alt text; the
  # author can change it before sending.
  defp alt(client_name) do
    client_name
    |> Path.rootname()
    |> String.replace(~r/[\[\]\(\)\\]/, "")
    |> String.trim()
    |> String.slice(0, 100)
    |> case do
      "" -> gettext("image")
      alt -> alt
    end
  end

  @doc "What to tell the user when an image is refused for `reason`."
  @spec error_text(atom()) :: String.t()
  def error_text(reason), do: message(reason)

  defp message(:too_large),
    do: gettext("This image is larger than %{mb} MB.", mb: div(Uploads.max_bytes(), 1_000_000))

  defp message(:not_accepted), do: gettext("Only JPEG, PNG, GIF and WebP images can be added.")
  defp message(:not_an_image), do: gettext("Only JPEG, PNG, GIF and WebP images can be added.")
  defp message(:too_many_pixels), do: gettext("This image has too many pixels.")
  defp message(:too_many_files), do: gettext("Add one image at a time.")

  defp message(:rate_limited),
    do: gettext("You have added many images lately. Please try again later.")

  defp message(_), do: gettext("This image could not be added.")
end

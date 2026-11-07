# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.TopicIconsLive do
  @moduledoc """
  Admin panel: topic icons (Topic Type, steward request, 2026-11-07). The images a topic in a
  "Topical" category may show instead of its starter, chosen in a dialog when it starts and
  by moderators later. Each has a name (its text alternative). Added and deleted here
  (`Idejo.Forum.TopicIcons`); an image is fitted inside 128 px.
  """
  use IdejoWeb, :live_view

  alias Idejo.Forum.TopicIcons
  alias Idejo.Uploads
  alias IdejoWeb.ImageUploads

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Topic icons"))
     |> assign(:icons, TopicIcons.list())
     |> assign(:form, to_form(TopicIcons.change(), as: :icon))
     |> assign(:image_error, nil)
     |> allow_upload(:image,
       accept: Uploads.extensions(),
       max_entries: 1,
       max_file_size: Uploads.max_bytes()
     )}
  end

  defp admin(socket), do: socket.assigns.current_scope.user

  @impl true
  def handle_event("validate", %{"icon" => params}, socket) do
    form = params |> TopicIcons.change() |> Map.put(:action, :validate)
    {:noreply, socket |> assign(:form, to_form(form, as: :icon)) |> ImageUploads.check(:image)}
  end

  def handle_event("save", %{"icon" => params}, socket) do
    results =
      consume_uploaded_entries(socket, :image, fn %{path: path}, _entry ->
        {:ok, TopicIcons.create(admin(socket), path, params)}
      end)

    case results do
      [{:ok, _icon}] ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Icon added."))
         |> assign(:icons, TopicIcons.list())
         |> assign(:form, to_form(TopicIcons.change(), as: :icon))
         |> assign(:image_error, nil)}

      [{:error, %Ecto.Changeset{} = changeset}] ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :icon))}

      [{:error, reason}] ->
        {:noreply, assign(socket, :image_error, ImageUploads.error_text(reason))}

      [] ->
        {:noreply, assign(socket, :image_error, gettext("Choose an image first."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case TopicIcons.get(id) do
      nil ->
        {:noreply, socket}

      icon ->
        {:ok, _} = TopicIcons.delete(admin(socket), icon)

        {:noreply,
         socket |> put_flash(:info, gettext("Icon deleted.")) |> assign(:icons, TopicIcons.list())}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:topic_icons}>
      <.header>
        {gettext("Topic icons")}
        <:subtitle>
          {gettext(
            "Topics in a category whose Topic Type is Topical show one of these instead of who started them."
          )}
        </:subtitle>
      </.header>

      <p :if={@icons == []} id="no-topic-icons">{gettext("No topic icons yet.")}</p>

      <ul :if={@icons != []} id="topic-icons" class="space-y-2">
        <li
          :for={icon <- @icons}
          id={"topic-icon-#{icon.id}"}
          class="flex items-center gap-3 rounded border border-base-300 p-3"
        >
          <img src={TopicIcons.url(icon)} alt="" class="topic-icon-preview" />
          <span class="font-semibold">{icon.name}</span>
          <span class="flex-1"></span>
          <button
            type="button"
            class="btn btn-xs btn-error"
            phx-click="delete"
            phx-value-id={icon.id}
            data-confirm={
              gettext("Delete the icon “%{name}”? Topics showing it will show none.",
                name: icon.name
              )
            }
            aria-label={gettext("Delete %{name}", name: icon.name)}
          >
            {gettext("Delete")}
          </button>
        </li>
      </ul>

      <section class="mt-8" aria-labelledby="topic-icon-form-heading">
        <h2 id="topic-icon-form-heading" class="font-semibold mb-2">{gettext("New icon")}</h2>
        <.form for={@form} id="topic-icon-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} type="text" label={gettext("Name")} maxlength="60" required />
          <label class="flex flex-col gap-1 text-sm mb-3">
            <span>{gettext("Image (JPEG, PNG, GIF or WebP)")}</span>
            <.live_file_input upload={@uploads.image} class="file-input file-input-sm" />
          </label>
          <p :if={@image_error} id="topic-icon-image-error" class="text-sm text-error mb-3">
            {@image_error}
          </p>
          <.button class="btn btn-primary">{gettext("Add icon")}</.button>
        </.form>
      </section>
    </Layouts.admin>
    """
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.InfoBoxesLive do
  @moduledoc """
  Admin panel: info boxes (steward decision, 2026-10-25). Cards shown to everyone before the
  categories on the home page, drawn like them: a title, an icon and a colour (the
  categories' picker, `IdejoWeb.Admin.look/1`) and Markdown text written in the message
  editor (TP-02). Made, changed, reordered and deleted here (`Idejo.Settings.InfoBoxes`);
  one form, for a new box or the one being edited.
  """
  use IdejoWeb, :live_view

  alias Idejo.Settings.InfoBoxes
  alias IdejoWeb.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Info boxes"))
     |> assign(:boxes, InfoBoxes.list())
     |> start_form(nil)}
  end

  # The form for a new box (`nil`) or for `box`.
  defp start_form(socket, box) do
    socket
    |> assign(:editing, box)
    |> assign(:form, to_form(InfoBoxes.change(box || %Idejo.Settings.InfoBox{}), as: :box))
    |> assign(editor_mode: :write, preview_html: "")
  end

  defp admin(socket), do: socket.assigns.current_scope.user
  defp find(socket, id), do: Enum.find(socket.assigns.boxes, &(&1.id == id))
  defp reload(socket), do: assign(socket, :boxes, InfoBoxes.list())

  @impl true
  # The preview follows the form; the colour picker fills in the hex field.
  def handle_event("validate", %{"box" => params} = all, socket) do
    params = Admin.picked_colour(params, all)

    form =
      (socket.assigns.editing || %Idejo.Settings.InfoBox{})
      |> InfoBoxes.change(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(form, as: :box))}
  end

  def handle_event("editor_mode", %{"mode" => "preview"}, socket) do
    body = socket.assigns.form[:body_md].value || ""

    {:noreply,
     assign(socket,
       editor_mode: :preview,
       preview_html: InfoBoxes.to_html(body, admin(socket))
     )}
  end

  def handle_event("editor_mode", %{"mode" => "write"}, socket),
    do: {:noreply, assign(socket, :editor_mode, :write)}

  # TP-10: suggestions while typing an inline link.
  def handle_event("suggest", params, socket), do: IdejoWeb.Suggestions.reply(socket, params)

  def handle_event("save", %{"box" => params}, socket) do
    result =
      case socket.assigns.editing do
        nil -> InfoBoxes.create(admin(socket), params)
        box -> InfoBoxes.update(admin(socket), box, params)
      end

    case result do
      {:ok, box} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Info box “%{title}” saved.", title: box.title))
         |> reload()
         |> start_form(nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :box), editor_mode: :write)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case find(socket, id) do
      nil -> {:noreply, reload(socket)}
      box -> {:noreply, start_form(socket, box)}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, start_form(socket, nil)}

  def handle_event("move", %{"id" => id, "direction" => direction}, socket)
      when direction in ["up", "down"] do
    with %{} = box <- find(socket, id) do
      InfoBoxes.move(admin(socket), box, String.to_existing_atom(direction))
    end

    {:noreply, reload(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case find(socket, id) do
      nil ->
        {:noreply, reload(socket)}

      box ->
        {:ok, _} = InfoBoxes.delete(admin(socket), box)
        editing = socket.assigns.editing

        socket =
          socket
          |> put_flash(:info, gettext("Info box “%{title}” deleted.", title: box.title))
          |> reload()

        {:noreply, if(editing && editing.id == box.id, do: start_form(socket, nil), else: socket)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:info_boxes}>
      <.header>
        {gettext("Info boxes")}
        <:subtitle>
          {gettext(
            "Cards shown to everyone before the categories on the home page, in this order, with your own text."
          )}
        </:subtitle>
      </.header>

      <p :if={@boxes == []} id="no-info-boxes">{gettext("No info boxes yet.")}</p>

      <ol id="info-boxes" class="space-y-2">
        <li
          :for={{box, index} <- Enum.with_index(@boxes)}
          id={"info-box-#{box.id}"}
          class="flex flex-wrap items-center gap-3 rounded border border-base-300 p-3"
        >
          <TopicComponents.category_mark category={IdejoWeb.PageHTML.info_box_mark(box)} />
          <span class="font-semibold">{box.title}</span>
          <span :if={@editing && @editing.id == box.id} class="badge badge-sm">
            {gettext("Editing")}
          </span>
          <span class="flex-1"></span>
          <button
            :if={index > 0}
            type="button"
            class="btn btn-xs"
            phx-click="move"
            phx-value-id={box.id}
            phx-value-direction="up"
            aria-label={gettext("Move %{name} up", name: box.title)}
          >
            <.icon name="hero-arrow-up" />
          </button>
          <button
            :if={index < length(@boxes) - 1}
            type="button"
            class="btn btn-xs"
            phx-click="move"
            phx-value-id={box.id}
            phx-value-direction="down"
            aria-label={gettext("Move %{name} down", name: box.title)}
          >
            <.icon name="hero-arrow-down" />
          </button>
          <button
            type="button"
            class="btn btn-xs"
            phx-click="edit"
            phx-value-id={box.id}
            aria-label={gettext("Edit %{name}", name: box.title)}
          >
            {gettext("Edit")}
          </button>
          <button
            type="button"
            class="btn btn-xs btn-error"
            phx-click="delete"
            phx-value-id={box.id}
            data-confirm={gettext("Delete the info box “%{name}”?", name: box.title)}
            aria-label={gettext("Delete %{name}", name: box.title)}
          >
            {gettext("Delete")}
          </button>
        </li>
      </ol>

      <section class="mt-8" aria-labelledby="info-box-form-heading">
        <h2 id="info-box-form-heading" class="font-semibold mb-2">
          {if @editing,
            do: gettext("Edit “%{name}”", name: @editing.title),
            else: gettext("New info box")}
        </h2>
        <.form for={@form} id="info-box-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:title]} type="text" label={gettext("Title")} required />
          <Admin.look
            form={@form}
            id="info-box"
            item_id={@editing && @editing.id}
            name_field={:title}
          />
          <MessageComponents.editor
            field={@form[:body_md]}
            label={gettext("Text (Markdown)")}
            mode={@editor_mode}
            preview_html={@preview_html}
          />
          <div class="flex gap-2">
            <.button class="btn btn-primary">
              {if @editing, do: gettext("Save"), else: gettext("Create info box")}
            </.button>
            <button :if={@editing} type="button" class="btn" phx-click="cancel">
              {gettext("Cancel")}
            </button>
          </div>
        </.form>
      </section>
    </Layouts.admin>
    """
  end
end

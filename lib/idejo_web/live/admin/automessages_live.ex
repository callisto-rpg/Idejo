# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.AutomessagesLive do
  @moduledoc """
  Admin panel: automessages (steward decision, 2026-11-01). `!command`s that moderators type
  in the composer to have the server post a text, sent by a server account with its own
  username and picture (`Idejo.Messages.Automessages`). One form, for a new automessage or
  the one being edited; the picture is uploaded with the form and set when it is saved.
  """
  use IdejoWeb, :live_view

  alias Idejo.Messages.Automessage
  alias Idejo.Messages.Automessages
  alias Idejo.Uploads
  alias IdejoWeb.ImageUploads
  alias IdejoWeb.UserComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Automessages"))
     |> assign(:automessages, Automessages.list())
     |> assign(:image_error, nil)
     |> allow_upload(:picture,
       accept: Uploads.extensions(),
       max_entries: 1,
       max_file_size: Uploads.max_bytes()
     )
     |> start_form(nil)}
  end

  # The form for a new automessage (`nil`) or for `automessage`.
  defp start_form(socket, automessage) do
    socket
    |> assign(:editing, automessage)
    |> assign(
      :form,
      to_form(Automessages.change(automessage || %Automessage{}), as: :automessage)
    )
    |> assign(editor_mode: :write, preview_html: "", image_error: nil)
  end

  defp admin(socket), do: socket.assigns.current_scope.user
  defp find(socket, id), do: Enum.find(socket.assigns.automessages, &(&1.id == id))
  defp reload(socket), do: assign(socket, :automessages, Automessages.list())

  @impl true
  def handle_event("validate", %{"automessage" => params}, socket) do
    form =
      (socket.assigns.editing || %Automessage{})
      |> Automessages.change(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(form, as: :automessage))
     |> ImageUploads.check(:picture)}
  end

  def handle_event("validate", _params, socket),
    do: {:noreply, ImageUploads.check(socket, :picture)}

  def handle_event("editor_mode", %{"mode" => "preview"}, socket) do
    body = socket.assigns.form[:body_md].value || ""

    {:noreply,
     assign(socket,
       editor_mode: :preview,
       preview_html: Automessages.preview(body, admin(socket))
     )}
  end

  def handle_event("editor_mode", %{"mode" => "write"}, socket),
    do: {:noreply, assign(socket, :editor_mode, :write)}

  # TP-10: suggestions while typing an inline link.
  def handle_event("suggest", params, socket), do: IdejoWeb.Suggestions.reply(socket, params)

  def handle_event("save", %{"automessage" => params}, socket) do
    editing = socket.assigns.editing

    save = fn picture ->
      case editing do
        nil -> Automessages.create(admin(socket), params, picture)
        automessage -> Automessages.update(admin(socket), automessage, params, picture)
      end
    end

    result =
      case consume_uploaded_entries(socket, :picture, fn %{path: path}, _entry ->
             {:ok, save.(path)}
           end) do
        [result] -> result
        [] -> save.(nil)
      end

    case result do
      {:ok, automessage} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Automessage !%{command} saved.", command: automessage.command)
         )
         |> reload()
         |> start_form(nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, form: to_form(changeset, as: :automessage), editor_mode: :write)}

      {:error, reason} ->
        {:noreply, assign(socket, :image_error, ImageUploads.error_text(reason))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case find(socket, id) do
      nil -> {:noreply, reload(socket)}
      automessage -> {:noreply, start_form(socket, automessage)}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, start_form(socket, nil)}

  def handle_event("delete", %{"id" => id}, socket) do
    case find(socket, id) do
      nil ->
        {:noreply, reload(socket)}

      automessage ->
        {:ok, _} = Automessages.delete(admin(socket), automessage)
        editing = socket.assigns.editing

        socket =
          socket
          |> put_flash(
            :info,
            gettext("Automessage !%{command} deleted.", command: automessage.command)
          )
          |> reload()

        {:noreply,
         if(editing && editing.id == automessage.id, do: start_form(socket, nil), else: socket)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:automessages}>
      <.header>
        {gettext("Automessages")}
        <:subtitle>
          {gettext(
            "Commands for moderators: typing !command in a topic's composer has the server post its text there, sent by the account you choose. Only moderators of the topic's category see them, unless you allow everyone."
          )}
        </:subtitle>
      </.header>

      <p :if={@automessages == []} id="no-automessages">{gettext("No automessages yet.")}</p>

      <ul id="automessages" class="space-y-2">
        <li
          :for={automessage <- @automessages}
          id={"automessage-#{automessage.id}"}
          class="flex flex-wrap items-center gap-3 rounded border border-base-300 p-3"
        >
          <span class="font-mono font-semibold">!{automessage.command}</span>
          <UserComponents.avatar user={automessage.sender} />
          <span>{automessage.sender.username}</span>
          <span :if={automessage.everyone} class="badge badge-sm">{gettext("Everyone")}</span>
          <span :if={automessage.cooldown_minutes > 0} class="badge badge-sm">
            {ngettext(
              "Waits 1 minute",
              "Waits %{count} minutes",
              automessage.cooldown_minutes
            )}
          </span>
          <span :if={@editing && @editing.id == automessage.id} class="badge badge-sm">
            {gettext("Editing")}
          </span>
          <span class="flex-1"></span>
          <button
            type="button"
            class="btn btn-xs"
            phx-click="edit"
            phx-value-id={automessage.id}
            aria-label={gettext("Edit !%{command}", command: automessage.command)}
          >
            {gettext("Edit")}
          </button>
          <button
            type="button"
            class="btn btn-xs btn-error"
            phx-click="delete"
            phx-value-id={automessage.id}
            data-confirm={
              gettext("Delete the automessage !%{command}?", command: automessage.command)
            }
            aria-label={gettext("Delete !%{command}", command: automessage.command)}
          >
            {gettext("Delete")}
          </button>
        </li>
      </ul>

      <section class="mt-8" aria-labelledby="automessage-form-heading">
        <h2 id="automessage-form-heading" class="font-semibold mb-2">
          {if @editing,
            do: gettext("Edit !%{command}", command: @editing.command),
            else: gettext("New automessage")}
        </h2>
        <.form for={@form} id="automessage-form" phx-change="validate" phx-submit="save">
          <.input
            field={@form[:command]}
            type="text"
            label={gettext("Command (typed as !command)")}
            required
          />
          <MessageComponents.editor
            field={@form[:body_md]}
            label={gettext("Message (Markdown)")}
            mode={@editor_mode}
            preview_html={@preview_html}
          />
          <.input
            field={@form[:everyone]}
            type="checkbox"
            label={gettext("Allow everyone to use this command")}
          />
          <p class="text-sm opacity-70 mb-2">
            {gettext(
              "On, anyone who may post in a topic can use it there; off, only its category's moderators."
            )}
          </p>
          <.input
            field={@form[:cooldown_minutes]}
            type="number"
            min="0"
            max={Idejo.Messages.Automessage.max_cooldown()}
            label={gettext("Wait before it can be used again (minutes)")}
            required
          />
          <p class="text-sm opacity-70 mb-2">
            {gettext(
              "Once posted in a topic, the command waits this long before anyone can use it there again. 0: no wait."
            )}
          </p>
          <.input
            field={@form[:sender_username]}
            type="text"
            label={gettext("Sender's username")}
            required
          />
          <p class="text-sm opacity-70 mb-2">
            {gettext(
              "A server account with this name sends the message. Automessages with the same name share its account and picture; until you upload one, it shows the Idejo picture."
            )}
          </p>
          <div class="flex items-center gap-3 mb-4">
            <UserComponents.avatar :if={@editing} user={@editing.sender} size={:medium} />
            <label for={@uploads.picture.ref} class="label">
              {gettext("Sender's picture (optional)")}
            </label>
            <.live_file_input upload={@uploads.picture} class="file-input file-input-sm" />
          </div>
          <p :if={@image_error} id="automessage-picture-error" class="text-error mb-2">
            {@image_error}
          </p>
          <div class="flex gap-2">
            <.button class="btn btn-primary">
              {if @editing, do: gettext("Save"), else: gettext("Create automessage")}
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

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.InfoBoxesLive do
  @moduledoc """
  Admin panel: info boxes (steward decision, 2026-10-25). Cards shown to everyone before the
  categories on the home page, drawn like them: a title, an icon and a colour (the
  categories' picker, `IdejoWeb.Admin.look/1`) and Markdown text written in the message
  editor (TP-02). Made, changed, reordered and deleted here (`Idejo.Settings.InfoBoxes`);
  one form, for a new box or the one being edited.

  Each box's place (steward request, 2026-11-13): before the categories, or in a section of
  them (the first, a category group's, or "Other"), at the start or the end of its cards.

  First, the Onboarding section (steward request, 2026-11-22; `Idejo.Onboarding`): the
  onboarding topic, chosen by searching the forum's topics, with its category, icon and
  title; and the new user presentation question (`{onboarding.string.1}`). Opening the page
  starts the default onboarding topic when there is none.
  """
  use IdejoWeb, :live_view

  alias Idejo.Forum.TopicIcons
  alias Idejo.Onboarding
  alias Idejo.Settings.{InfoBox, InfoBoxes}
  alias IdejoWeb.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Onboarding and information"))
     |> assign(:boxes, InfoBoxes.list())
     |> assign(:groups, Idejo.Forum.list_groups())
     |> start_onboarding()
     |> start_form(nil)}
  end

  # Onboarding: the topic (started as the default when there is none and a category exists),
  # its form, the topic search and the question's form.
  defp start_onboarding(socket) do
    topic =
      case Onboarding.ensure() do
        {:ok, topic} -> topic
        {:error, _} -> nil
      end

    socket
    |> assign(:onboarding_topic, topic)
    |> assign(:onboarding_form, to_form(onboarding_params(topic), as: :onboarding))
    |> assign(:onboarding_icons, TopicIcons.list())
    |> assign(:onboarding_categories, onboarding_categories())
    |> assign(:topic_query, "")
    |> assign(:topic_results, [])
    |> assign(:question_form, to_form(%{"text" => Onboarding.string(1)}, as: :question))
  end

  defp onboarding_params(nil), do: %{}

  defp onboarding_params(topic),
    do: Map.new([:category_id, :icon_id, :title], &{Atom.to_string(&1), Map.fetch!(topic, &1)})

  defp onboarding_categories do
    Idejo.Forum.list_categories()
    |> Enum.reject(& &1.archive)
    |> Enum.map(&{&1.name, &1.id})
  end

  defp onboarding_error(:onboarding_topic), do: gettext("Choose a topic first.")
  defp onboarding_error(%Ecto.Changeset{}), do: gettext("The title cannot be blank.")
  defp onboarding_error(_), do: gettext("The onboarding topic could not be changed.")

  # The form for a new box (`nil`) or for `box`.
  defp start_form(socket, box) do
    socket
    |> assign(:editing, box)
    |> assign(:form, to_form(InfoBoxes.change(box || %InfoBox{}), as: :box))
    |> assign(editor_mode: :write, preview_html: "")
  end

  # The places a box can take, for the form.
  defp places(groups) do
    [
      {gettext("Before the categories"), "before"},
      {gettext("In the first section"), "first"}
    ] ++
      Enum.map(groups, &group_place/1) ++
      [{gettext("In “Other” (categories without a group)"), "other"}]
  end

  defp group_place(group),
    do: {gettext("In the section “%{name}”", name: group.name), "group:" <> group.id}

  # How the list says where a box is.
  defp place_label(box, groups) do
    place = InfoBox.place(box)
    {label, _} = Enum.find(places(groups), {nil, nil}, &(elem(&1, 1) == place))
    label = label || gettext("In the first section")

    cond do
      box.placement == "before" -> label
      box.at_end -> gettext("%{place}, at the end", place: label)
      true -> gettext("%{place}, at the start", place: label)
    end
  end

  defp admin(socket), do: socket.assigns.current_scope.user
  defp find(socket, id), do: Enum.find(socket.assigns.boxes, &(&1.id == id))
  defp reload(socket), do: assign(socket, :boxes, InfoBoxes.list())

  @impl true
  def handle_event("onboarding_search", %{"query" => query}, socket) do
    {:noreply, assign(socket, topic_query: query, topic_results: Onboarding.search(query))}
  end

  def handle_event("onboarding_choose", %{"id" => id}, socket) do
    with %{} = topic <- Enum.find(socket.assigns.topic_results, &(&1.id == id)),
         {:ok, topic} <- Onboarding.choose(admin(socket), topic) do
      {:noreply,
       socket
       |> start_onboarding()
       |> put_flash(:info, gettext("“%{title}” is the onboarding topic.", title: topic.title))}
    else
      error ->
        reason = with {:error, reason} <- error, do: reason
        {:noreply, put_flash(socket, :error, onboarding_error(reason))}
    end
  end

  def handle_event("onboarding_save", %{"onboarding" => params}, socket) do
    case Onboarding.update(admin(socket), params) do
      {:ok, _topic} ->
        {:noreply,
         socket
         |> start_onboarding()
         |> put_flash(:info, gettext("Onboarding topic saved."))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, onboarding_error(reason))}
    end
  end

  def handle_event("question_save", %{"question" => %{"text" => text}}, socket) do
    case Onboarding.save_question(admin(socket), text) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:question_form, to_form(%{"text" => Onboarding.string(1)}, as: :question))
         |> put_flash(:info, gettext("New user presentation question saved."))}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, gettext("The question cannot be blank or that long."))}
    end
  end

  # The preview follows the form; the colour picker fills in the hex field.
  def handle_event("validate", %{"box" => params} = all, socket) do
    params = Admin.picked_colour(params, all)

    form =
      (socket.assigns.editing || %InfoBox{})
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
        {gettext("Onboarding and information")}
        <:subtitle>
          {gettext(
            "Cards shown to everyone on the home page, before the categories or in a section of them, in this order, with your own text."
          )}
        </:subtitle>
      </.header>

      <%!-- Steward request, 2026-11-22. --%>
      <section id="onboarding" class="mb-10" aria-labelledby="onboarding-heading">
        <h2 id="onboarding-heading" class="text-lg font-semibold mb-2">
          {gettext("Onboarding")}
        </h2>

        <h3 class="font-semibold">{gettext("Onboarding topic")}</h3>
        <p class="text-sm opacity-70 mb-2">
          {gettext(
            "Always topical and followed by everyone. Moderators cannot delete or archive it while it is the onboarding topic."
          )}
        </p>
        <p :if={!@onboarding_topic} id="onboarding-none" class="text-sm">
          {gettext(
            "There is no onboarding topic yet: “Welcome” starts in the first category once there is one, or choose a topic below."
          )}
        </p>
        <p :if={@onboarding_topic} id="onboarding-current" class="flex items-center gap-2 mb-2">
          <TopicComponents.topic_icon topic={@onboarding_topic} size={:small} />
          <.link navigate={~p"/t/#{@onboarding_topic.id}/#{@onboarding_topic.slug}"}>
            {@onboarding_topic.title}
          </.link>
          <span class="text-sm opacity-70">{@onboarding_topic.category.name}</span>
        </p>

        <form
          id="onboarding-search"
          phx-change="onboarding_search"
          phx-submit="onboarding_search"
        >
          <label class="label mb-1" for="onboarding-search-query">
            {gettext("Choose another topic")}
          </label>
          <input
            id="onboarding-search-query"
            type="search"
            name="query"
            value={@topic_query}
            placeholder={gettext("Search the topics by title")}
            phx-debounce="300"
            autocomplete="off"
            class="input w-full"
          />
        </form>
        <ul :if={@topic_results != []} id="onboarding-results" class="mt-2 space-y-1">
          <li :for={topic <- @topic_results}>
            <button
              type="button"
              id={"onboarding-choose-#{topic.id}"}
              class="btn btn-sm btn-ghost"
              phx-click="onboarding_choose"
              phx-value-id={topic.id}
            >
              {topic.title}
              <span class="text-xs opacity-70">{topic.category.name}</span>
            </button>
          </li>
        </ul>
        <p
          :if={@topic_query != "" and @topic_results == []}
          id="onboarding-no-results"
          class="text-sm mt-2"
        >
          {gettext("No topic matches.")}
        </p>

        <.form
          :if={@onboarding_topic}
          for={@onboarding_form}
          id="onboarding-form"
          phx-submit="onboarding_save"
          class="mt-4"
        >
          <.input
            field={@onboarding_form[:category_id]}
            type="select"
            label={gettext("Category")}
            options={@onboarding_categories}
          />
          <.input
            field={@onboarding_form[:icon_id]}
            type="select"
            label={gettext("Topic icon")}
            options={Enum.map(@onboarding_icons, &{&1.name, &1.id})}
          />
          <.input
            field={@onboarding_form[:title]}
            type="text"
            label={gettext("Topic title")}
            required
          />
          <.button class="btn btn-primary">{gettext("Save onboarding topic")}</.button>
        </.form>

        <.form
          for={@question_form}
          id="onboarding-question-form"
          phx-submit="question_save"
          class="mt-6"
        >
          <.input
            field={@question_form[:text]}
            type="textarea"
            label={gettext("New user presentation question")}
            maxlength="2000"
            required
          />
          <.button class="btn btn-primary">{gettext("Save question")}</.button>
        </.form>
      </section>

      <h2 class="text-lg font-semibold mb-2">{gettext("Information")}</h2>

      <p :if={@boxes == []} id="no-info-boxes">{gettext("No info boxes yet.")}</p>

      <ol id="info-boxes" class="space-y-2">
        <li
          :for={{box, index} <- Enum.with_index(@boxes)}
          id={"info-box-#{box.id}"}
          class="flex flex-wrap items-center gap-3 rounded border border-base-300 p-3"
        >
          <TopicComponents.category_mark category={IdejoWeb.PageHTML.info_box_mark(box)} />
          <span class="font-semibold">{box.title}</span>
          <span id={"info-box-#{box.id}-place"} class="text-sm opacity-70">
            {place_label(box, @groups)}
          </span>
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
          <.input
            field={@form[:show_head]}
            type="checkbox"
            label={gettext("Show title and icon")}
          />
          <%!-- Steward request, 2026-11-13. --%>
          <.input
            field={@form[:place]}
            type="select"
            label={gettext("Place on the home page")}
            options={places(@groups)}
          />
          <.input
            :if={@form[:place].value != "before"}
            field={@form[:at_end]}
            type="checkbox"
            label={gettext("At the end of the section, after its categories")}
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

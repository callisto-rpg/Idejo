# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.CategoriesLive do
  @moduledoc """
  Admin panel: categories (RP-03). Create, rename, describe, reorder and delete the
  categories of the server; one level only. Each may have an icon and a colour (`#rrggbb`,
  typed or picked; steward decision, 2026-10-23), with a preview of its mark. Deleting a category that has topics asks whether
  to move them to another category or archive them; the Archive itself is never deleted.
  """
  use IdejoWeb, :live_view

  alias Idejo.Forum
  alias Idejo.Forum.{Category, CategoryIcons}
  alias IdejoWeb.CategoryIconNames

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Categories"))
     |> assign(:editing, nil)
     |> assign(:deleting, nil)
     |> assign(:new_form, to_form(Forum.change_new_category(), as: :category))
     |> load()}
  end

  defp load(socket),
    do: assign(socket, categories: Forum.list_categories(), topics: Forum.topic_counts())

  defp topic_count(topics, category), do: Map.get(topics, category.id, 0)
  defp admin(socket), do: socket.assigns.current_scope.user
  defp find(socket, id), do: Enum.find(socket.assigns.categories, &(&1.id == id))

  @impl true
  def handle_event("create", %{"category" => params}, socket) do
    case Forum.create_category(admin(socket), params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Category “%{name}” created.", name: category.name))
         |> assign(:new_form, to_form(Forum.change_new_category(), as: :category))
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_form(changeset, as: :category))}
    end
  end

  # The preview follows the form; the colour picker fills in the hex field.
  def handle_event("validate_new", %{"category" => params} = all, socket) do
    params = picked_colour(params, all)
    form = params |> Forum.change_new_category() |> Map.put(:action, :validate)
    {:noreply, assign(socket, :new_form, to_form(form, as: :category))}
  end

  def handle_event("validate_edit", %{"id" => id, "edit" => params} = all, socket) do
    params = picked_colour(params, all)
    form = socket |> find(id) |> Forum.change_category(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :editing, {id, to_form(form, as: :edit)})}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    category = find(socket, id)

    {:noreply,
     assign(socket, :editing, {category.id, to_form(Forum.change_category(category), as: :edit)})}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("update", %{"id" => id, "edit" => params}, socket) do
    case Forum.update_category(admin(socket), find(socket, id), params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Category “%{name}” saved.", name: category.name))
         |> assign(:editing, nil)
         |> assign(:deleting, nil)
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, :editing, {id, to_form(changeset, as: :edit)})}
    end
  end

  def handle_event("move", %{"id" => id, "direction" => direction}, socket)
      when direction in ["up", "down"] do
    direction = String.to_existing_atom(direction)

    case Forum.move_category(admin(socket), find(socket, id), direction) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, :at_edge} -> {:noreply, load(socket)}
    end
  end

  # A category with topics asks where they go before it is deleted.
  def handle_event("ask_delete", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :deleting, id)}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, :deleting, nil)}

  def handle_event("delete", %{"id" => id} = params, socket) do
    category = find(socket, id)

    case Forum.delete_category(admin(socket), category, topics: topics_option(socket, params)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Category “%{name}” deleted.", name: category.name))
         |> assign(:deleting, nil)
         |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, delete_error(reason, category)) |> load()}
    end
  end

  defp picked_colour(params, %{"_target" => [_, "colour_picker"]}),
    do: Map.put(params, "colour", params["colour_picker"])

  defp picked_colour(params, _all), do: params

  defp topics_option(_socket, %{"topics" => "archive"}), do: :archive

  defp topics_option(socket, %{"topics" => "move:" <> target_id}) do
    case find(socket, target_id) do
      nil -> nil
      target -> {:move, target}
    end
  end

  defp topics_option(_socket, _params), do: nil

  defp delete_error(:has_topics, category),
    do: gettext("Choose where the topics of “%{name}” go.", name: category.name)

  defp delete_error(:invalid_target, _category),
    do: gettext("Choose another category to move the topics to.")

  defp delete_error(:archive, _category), do: gettext("The Archive cannot be deleted.")
  defp delete_error(_reason, _category), do: gettext("The category could not be deleted.")

  attr :form, :any, required: true
  attr :id, :string, required: true
  attr :category_id, :any, required: true

  # RP-03: the colour (typed, or picked with the browser's colour picker) and the icon, with a
  # preview of the mark as it will show.
  defp look(assigns) do
    form = assigns.form
    colour = valid(form, :colour)
    tint = if assigns.category_id, do: CategoryIcons.tint(assigns.category_id), else: "#6567e7"

    preview = %Category{
      id: assigns.category_id || "new",
      name: form[:name].value || "?",
      icon: valid(form, :icon),
      colour: colour
    }

    assigns =
      assign(assigns,
        preview: preview,
        tile: colour || tint,
        icon: form[:icon].value || ""
      )

    ~H"""
    <div class="category-look">
      <div class="category-look-preview" aria-hidden="true">
        <TopicComponents.category_mark category={@preview} size={:large} />
      </div>
      <div class="category-look-colour">
        <.input
          field={@form[:colour]}
          type="text"
          label={gettext("Colour (#rrggbb, empty for the default)")}
          placeholder="#3366ff"
          spellcheck="false"
        />
        <label class="category-look-picker">
          <span class="sr-only">{gettext("Pick a colour")}</span>
          <input
            type="color"
            name={@form[:colour_picker].name}
            id={"#{@id}-colour-picker"}
            value={@tile}
          />
        </label>
      </div>
    </div>
    <fieldset class="icon-picker">
      <legend class="label mb-1">{gettext("Icon")}</legend>
      <label class="icon-choice icon-choice-none">
        <input type="radio" name={@form[:icon].name} value="" checked={@icon == ""} />
        <span>{gettext("No icon")}</span>
      </label>
      <fieldset :for={{group, ids} <- CategoryIcons.groups()} class="icon-group">
        <legend>{CategoryIconNames.group_name(group)}</legend>
        <div class="icon-choices">
          <label :for={id <- ids} class="icon-choice" title={CategoryIconNames.name(id)}>
            <input type="radio" name={@form[:icon].name} value={id} checked={@icon == id} />
            <svg viewBox="0 0 32 32" aria-hidden="true" focusable="false">
              <TopicComponents.icon_shapes shapes={CategoryIcons.shapes(id, @tile)} />
            </svg>
            <span class="sr-only">{CategoryIconNames.name(id)}</span>
          </label>
        </div>
      </fieldset>
    </fieldset>
    """
  end

  # A field's value only when it passed validation, for the preview.
  defp valid(form, field) do
    if Keyword.has_key?(form.errors, field), do: nil, else: blank_to_nil(form[field].value)
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:categories}>
      <.header>
        {gettext("Categories")}
        <:subtitle>
          {gettext(
            "Shown on the home page in this order. Who can see and post in each is set under Permissions."
          )}
        </:subtitle>
      </.header>

      <p :if={@categories == []} id="no-categories">
        {gettext("No categories yet. Create the first one below, e.g. Announcements, General, Help.")}
      </p>

      <ol id="categories" class="space-y-2">
        <li
          :for={{category, index} <- Enum.with_index(@categories)}
          id={"category-#{category.id}"}
          class="rounded border border-base-300 p-3"
        >
          <%= case @editing do %>
            <% {id, form} when id == category.id -> %>
              <.form
                for={form}
                id={"edit-category-#{category.id}"}
                phx-change="validate_edit"
                phx-submit="update"
                phx-value-id={category.id}
              >
                <.input field={form[:name]} type="text" label={gettext("Name")} required />
                <.input field={form[:description]} type="textarea" label={gettext("Description")} />
                <.look form={form} id={"edit-#{category.id}"} category_id={category.id} />
                <div class="flex gap-2">
                  <.button class="btn btn-primary btn-sm">{gettext("Save")}</.button>
                  <button type="button" class="btn btn-sm" phx-click="cancel_edit">
                    {gettext("Cancel")}
                  </button>
                </div>
              </.form>
            <% _ -> %>
              <div class="flex flex-wrap items-center gap-3">
                <span class="font-semibold">{category.name}</span>
                <span :if={category.archive} class="badge badge-sm">{gettext("Archive")}</span>
                <code class="text-sm opacity-70">/c/{category.slug}</code>
                <span class="text-sm opacity-70">
                  {ngettext("1 topic", "%{count} topics", topic_count(@topics, category))}
                </span>
                <span class="flex-1"></span>
                <button
                  :if={index > 0}
                  type="button"
                  class="btn btn-xs"
                  phx-click="move"
                  phx-value-id={category.id}
                  phx-value-direction="up"
                  aria-label={gettext("Move %{name} up", name: category.name)}
                >
                  <.icon name="hero-arrow-up" />
                </button>
                <button
                  :if={index < length(@categories) - 1}
                  type="button"
                  class="btn btn-xs"
                  phx-click="move"
                  phx-value-id={category.id}
                  phx-value-direction="down"
                  aria-label={gettext("Move %{name} down", name: category.name)}
                >
                  <.icon name="hero-arrow-down" />
                </button>
                <.link
                  navigate={~p"/admin/permissions/#{category.slug}"}
                  class="btn btn-xs"
                  aria-label={gettext("Permissions of %{name}", name: category.name)}
                >
                  {gettext("Permissions")}
                </.link>
                <button
                  type="button"
                  class="btn btn-xs"
                  phx-click="edit"
                  phx-value-id={category.id}
                  aria-label={gettext("Edit %{name}", name: category.name)}
                >
                  {gettext("Edit")}
                </button>
                <button
                  :if={!category.archive and topic_count(@topics, category) == 0}
                  type="button"
                  class="btn btn-xs btn-error"
                  phx-click="delete"
                  phx-value-id={category.id}
                  data-confirm={gettext("Delete the category “%{name}”?", name: category.name)}
                >
                  {gettext("Delete")}
                </button>
                <button
                  :if={!category.archive and topic_count(@topics, category) > 0}
                  type="button"
                  class="btn btn-xs btn-error"
                  phx-click="ask_delete"
                  phx-value-id={category.id}
                >
                  {gettext("Delete")}
                </button>
              </div>
              <p :if={category.description != ""} class="text-sm mt-1">{category.description}</p>
              <.form
                :if={@deleting == category.id}
                for={%{}}
                as={:delete}
                id={"delete-category-#{category.id}"}
                phx-submit="delete"
                phx-value-id={category.id}
                class="mt-3 space-y-2"
              >
                <fieldset>
                  <legend class="text-sm font-semibold">
                    {ngettext(
                      "“%{name}” has 1 topic. Where should it go?",
                      "“%{name}” has %{count} topics. Where should they go?",
                      topic_count(@topics, category),
                      name: category.name
                    )}
                  </legend>
                  <label
                    :for={target <- @categories}
                    :if={target.id != category.id and !target.archive}
                    class="flex items-center gap-2"
                  >
                    <input type="radio" name="topics" value={"move:#{target.id}"} required />
                    {gettext("Move to %{name}", name: target.name)}
                  </label>
                  <label class="flex items-center gap-2">
                    <input type="radio" name="topics" value="archive" required />
                    {gettext("Archive (read only, hidden unless shown in Permissions)")}
                  </label>
                </fieldset>
                <div class="flex gap-2">
                  <.button class="btn btn-error btn-sm">
                    {gettext("Delete “%{name}”", name: category.name)}
                  </.button>
                  <button type="button" class="btn btn-sm" phx-click="cancel_delete">
                    {gettext("Cancel")}
                  </button>
                </div>
              </.form>
          <% end %>
        </li>
      </ol>

      <section class="mt-8" aria-labelledby="new-category-heading">
        <h2 id="new-category-heading" class="font-semibold mb-2">{gettext("New category")}</h2>
        <.form
          for={@new_form}
          id="new-category-form"
          phx-change="validate_new"
          phx-submit="create"
        >
          <.input field={@new_form[:name]} type="text" label={gettext("Name")} required />
          <.input field={@new_form[:description]} type="textarea" label={gettext("Description")} />
          <.look form={@new_form} id="new" category_id={nil} />
          <.input
            field={@new_form[:slug]}
            type="text"
            label={
              gettext("Web address /c/… (leave empty to make it from the name; it never changes)")
            }
            spellcheck="false"
          />
          <.button class="btn btn-primary">{gettext("Create category")}</.button>
        </.form>
      </section>
    </Layouts.admin>
    """
  end
end

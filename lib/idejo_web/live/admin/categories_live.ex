# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.CategoriesLive do
  @moduledoc """
  Admin panel: categories (RP-03). Create, rename, describe, reorder and delete the
  categories of the server; one level only.
  """
  use IdejoWeb, :live_view

  alias Idejo.Forum

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Categories"))
     |> assign(:editing, nil)
     |> assign(:new_form, to_form(Forum.change_new_category(), as: :category))
     |> load()}
  end

  defp load(socket), do: assign(socket, :categories, Forum.list_categories())
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

  def handle_event("delete", %{"id" => id}, socket) do
    category = find(socket, id)
    {:ok, _} = Forum.delete_category(admin(socket), category)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Category “%{name}” deleted.", name: category.name))
     |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:categories}>
      <.header>
        {gettext("Categories")}
        <:subtitle>
          {gettext("Shown on the home page in this order. Who can see and post in each comes next.")}
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
                phx-submit="update"
                phx-value-id={category.id}
              >
                <.input field={form[:name]} type="text" label={gettext("Name")} required />
                <.input field={form[:description]} type="textarea" label={gettext("Description")} />
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
                <code class="text-sm opacity-70">/c/{category.slug}</code>
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
                  type="button"
                  class="btn btn-xs btn-error"
                  phx-click="delete"
                  phx-value-id={category.id}
                  data-confirm={gettext("Delete the category “%{name}”?", name: category.name)}
                >
                  {gettext("Delete")}
                </button>
              </div>
              <p :if={category.description != ""} class="text-sm mt-1">{category.description}</p>
          <% end %>
        </li>
      </ol>

      <section class="mt-8" aria-labelledby="new-category-heading">
        <h2 id="new-category-heading" class="font-semibold mb-2">{gettext("New category")}</h2>
        <.form for={@new_form} id="new-category-form" phx-submit="create">
          <.input field={@new_form[:name]} type="text" label={gettext("Name")} required />
          <.input field={@new_form[:description]} type="textarea" label={gettext("Description")} />
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

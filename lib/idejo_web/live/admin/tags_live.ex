# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Admin.TagsLive do
  @moduledoc """
  Admin panel: topic tags (TP-19). Create tags for every category (server-wide, no category
  ticked) or for one or more (steward decision, 2026-11-14), rename them or change their
  categories (topics in a category that no longer offers one lose it), and delete them
  (topics lose them). Who may change a topic's tags is the "Edit tags" right in Permissions.
  """
  use IdejoWeb, :live_view

  alias Idejo.Forum
  alias Idejo.Forum.{Tag, Tags}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Tags"))
     |> assign(:editing, nil)
     |> assign(:new_form, to_form(Tags.change_tag(), as: :tag))
     |> load()}
  end

  defp load(socket) do
    categories = Enum.reject(Forum.list_categories(), & &1.archive)
    assign(socket, tags: Tags.list_tags(), counts: Tags.topic_counts(), categories: categories)
  end

  defp admin(socket), do: socket.assigns.current_scope.user
  defp find(socket, id), do: Enum.find(socket.assigns.tags, &(&1.id == id))
  defp topic_count(counts, tag), do: Map.get(counts, tag.id, 0)

  @impl true
  def handle_event("create", %{"tag" => params}, socket) do
    case Tags.create_tag(admin(socket), params) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Tag “%{name}” created.", name: tag.name))
         |> assign(:new_form, to_form(Tags.change_tag(), as: :tag))
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_form(changeset, as: :tag))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    tag = find(socket, id)
    {:noreply, assign(socket, :editing, {tag.id, to_form(Tags.change_tag(tag), as: :edit)})}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("update", %{"id" => id, "edit" => params}, socket) do
    case Tags.update_tag(admin(socket), find(socket, id), params) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Tag “%{name}” saved.", name: tag.name))
         |> assign(:editing, nil)
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, :editing, {id, to_form(changeset, as: :edit)})}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tag = find(socket, id)

    case Tags.delete_tag(admin(socket), tag) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Tag “%{name}” deleted.", name: tag.name))
         |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("The tag could not be deleted."))}
    end
  end

  defp where(%Tag{categories: []}), do: gettext("All categories")
  defp where(%Tag{categories: categories}), do: Enum.map_join(categories, ", ", & &1.name)

  # The categories ticked: a tag's own, or what a refused form sent back.
  defp ticked(%Phoenix.HTML.Form{params: %{"category_ids" => ids}}, _tag), do: List.wrap(ids)
  defp ticked(_form, %Tag{categories: categories}), do: Enum.map(categories, & &1.id)
  defp ticked(_form, nil), do: []

  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :categories, :list, required: true
  attr :ticked, :list, required: true

  # A checkbox per category; none ticked is a tag for every category. The hidden empty value
  # sends the list even when nothing is ticked.
  defp category_choice(assigns) do
    ~H"""
    <fieldset id={@id} class="w-full">
      <legend class="text-sm">
        {gettext("Categories (none ticked: all categories)")}
      </legend>
      <input type="hidden" name={@name} value="" />
      <div class="flex flex-wrap gap-x-4 gap-y-1">
        <label :for={category <- @categories} class="flex items-center gap-1 text-sm">
          <input
            type="checkbox"
            name={@name}
            value={category.id}
            checked={category.id in @ticked}
            class="checkbox checkbox-xs"
          />
          {category.name}
        </label>
      </div>
    </fieldset>
    """
  end

  defp delete_question(tag, 0), do: gettext("Delete the tag “%{name}”?", name: tag.name)

  defp delete_question(tag, count),
    do:
      ngettext(
        "Delete the tag “%{name}”? 1 topic loses it.",
        "Delete the tag “%{name}”? %{count} topics lose it.",
        count,
        name: tag.name
      )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} section={:tags}>
      <.header>
        {gettext("Tags")}
        <:subtitle>
          {gettext(
            "Starting a topic takes at least one tag when its category has any: the tags for all categories and its own. Who may change a topic's tags is set under Permissions (Edit tags)."
          )}
        </:subtitle>
      </.header>

      <p :if={@tags == []} id="no-tags">
        {gettext("No tags yet. Create the first one below, e.g. Question, Idea, Bug.")}
      </p>

      <ol id="tags" class="space-y-2">
        <li
          :for={tag <- @tags}
          id={"tag-#{tag.id}"}
          class="flex flex-wrap items-center gap-3 rounded border border-base-300 p-3"
        >
          <%= case @editing do %>
            <% {id, form} when id == tag.id -> %>
              <.form
                for={form}
                id={"edit-tag-#{tag.id}"}
                phx-submit="update"
                phx-value-id={tag.id}
                class="flex flex-wrap items-end gap-3 w-full"
              >
                <.input field={form[:name]} type="text" label={gettext("Name")} required />
                <.category_choice
                  id={"edit-tag-#{tag.id}-categories"}
                  name="edit[category_ids][]"
                  categories={@categories}
                  ticked={ticked(form, tag)}
                />
                <.button class="btn btn-primary btn-sm">{gettext("Save")}</.button>
                <button type="button" class="btn btn-sm" phx-click="cancel_edit">
                  {gettext("Cancel")}
                </button>
              </.form>
            <% _ -> %>
              <a href={TopicComponents.tag_path([tag])} class="tag-chip">{tag.name}</a>
              <span class="text-sm opacity-70">{where(tag)}</span>
              <span class="text-sm opacity-70">
                {ngettext("1 topic", "%{count} topics", topic_count(@counts, tag))}
              </span>
              <span class="flex-1"></span>
              <button
                type="button"
                class="btn btn-xs"
                phx-click="edit"
                phx-value-id={tag.id}
                aria-label={gettext("Edit %{name}", name: tag.name)}
              >
                {gettext("Edit")}
              </button>
              <button
                type="button"
                class="btn btn-xs btn-error"
                phx-click="delete"
                phx-value-id={tag.id}
                data-confirm={delete_question(tag, topic_count(@counts, tag))}
                aria-label={gettext("Delete %{name}", name: tag.name)}
              >
                {gettext("Delete")}
              </button>
          <% end %>
        </li>
      </ol>

      <section class="mt-8" aria-labelledby="new-tag-heading">
        <h2 id="new-tag-heading" class="font-semibold mb-2">{gettext("New tag")}</h2>
        <.form
          for={@new_form}
          id="new-tag-form"
          phx-submit="create"
          class="flex flex-wrap items-end gap-3"
        >
          <.input field={@new_form[:name]} type="text" label={gettext("Name")} required />
          <.category_choice
            id="new-tag-categories"
            name="tag[category_ids][]"
            categories={@categories}
            ticked={ticked(@new_form, nil)}
          />
          <.button class="btn btn-primary">{gettext("Create tag")}</.button>
        </.form>
      </section>
    </Layouts.admin>
    """
  end
end

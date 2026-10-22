# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.NewTopicLive do
  @moduledoc """
  New topic (TP-01) at `/c/{slug}/new`: a title and a first message, posted together. Only
  for users with the `:start` right in the category.

  The first message is written in the message editor every message uses (TP-02). Nobody
  else sees it while it is typed: nothing is stored or sent anywhere before "Post topic", and
  the preview is rendered for the author alone. It is then posted closed, with the title.

  The topic takes one or more tags (TP-19) among those its category offers (server-wide and
  its own), when there are any; in a topic from a message they follow the chosen category.

  At `/m/{id}/new-topic` it starts a topic from that message (TP-09, "New topic from this"):
  any message the user may view, shown as a linked excerpt, into any category where they may
  start topics (chosen in the form; the source's category first when allowed).
  """
  use IdejoWeb, :live_view

  alias Idejo.Forum
  alias Idejo.Forum.Tags
  alias Idejo.Messages.Body
  alias IdejoWeb.ImageUploads

  @impl true
  def mount(%{"id" => id}, _session, %{assigns: %{live_action: :fork}} = socket) do
    user = socket.assigns.current_scope.user

    case Forum.get_viewable_message(user, id) do
      # MO-02: a deleted message starts no topic.
      result when is_nil(result) or result.deleted_at != nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Messages.Message

      source ->
        source = Idejo.Repo.preload(source, :author)

        case Forum.list_startable_categories(user) do
          [] ->
            {:ok,
             socket
             |> put_flash(:error, gettext("You cannot start topics."))
             |> redirect(to: ~p"/m/#{source.id}")}

          categories ->
            default =
              Enum.find(categories, hd(categories), &(&1.id == source.topic.category_id))

            {:ok,
             socket
             |> assign(:page_title, gettext("New topic from a message"))
             |> assign(source: source, categories: categories, category: default)
             |> assign(:tags, Tags.available_tags(default))
             |> assign(:form, to_form(Forum.change_new_topic(), as: :topic))
             |> assign(editor_mode: :write, preview_html: "")
             |> ImageUploads.allow(:editor_image)}
        end
    end
  end

  def mount(%{"slug" => slug}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Forum.get_viewable_category(user, slug) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Category

      category ->
        if Forum.can_start_topic?(user, category) do
          {:ok,
           socket
           |> assign(:page_title, gettext("New topic in %{category}", category: category.name))
           |> assign(source: nil, categories: [], category: category)
           |> assign(:tags, Tags.available_tags(category))
           |> assign(:form, to_form(Forum.change_new_topic(), as: :topic))
           |> assign(editor_mode: :write, preview_html: "")
           |> ImageUploads.allow(:editor_image)}
        else
          {:ok,
           socket
           |> put_flash(:error, gettext("You cannot start topics in this category."))
           |> redirect(to: ~p"/c/#{category.slug}")}
        end
    end
  end

  @impl true
  def handle_event("validate", %{"topic" => params}, socket) do
    socket = choose_category(socket, params)
    form = params |> Forum.change_new_topic(socket.assigns.tags) |> Map.put(:action, :validate)

    {:noreply,
     socket |> assign(:form, to_form(form, as: :topic)) |> ImageUploads.check(:editor_image)}
  end

  def handle_event("editor_mode", %{"mode" => "preview"}, socket) do
    body = socket.assigns.form.params["body"] || ""

    {:noreply,
     assign(socket,
       editor_mode: :preview,
       preview_html:
         Body.to_html(body,
           author: socket.assigns.current_scope.user,
           category_id: socket.assigns.category.id
         )
     )}
  end

  def handle_event("editor_mode", %{"mode" => "write"}, socket),
    do: {:noreply, assign(socket, :editor_mode, :write)}

  def handle_event("post", %{"topic" => params}, socket) do
    user = socket.assigns.current_scope.user

    {category, opts} = target(socket, params)

    case Forum.create_topic(user, category, params, opts) do
      {:ok, topic} ->
        {:noreply, redirect(socket, to: ~p"/t/#{topic.id}/#{topic.slug}")}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You cannot start topics in this category."))
         |> redirect(to: ~p"/c/#{category.slug}")}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("You have started many topics lately. Please try again later.")
         )}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form, as: :topic))}
    end
  end

  # From a message, the tags on offer follow the category chosen in the form.
  defp choose_category(%{assigns: %{source: nil}} = socket, _params), do: socket

  defp choose_category(socket, params) do
    {category, _opts} = target(socket, params)

    if category.id == socket.assigns.category.id,
      do: socket,
      else: assign(socket, category: category, tags: Tags.available_tags(category))
  end

  # A topic from a message goes to the chosen category, one the user may start topics in.
  defp target(%{assigns: %{source: nil, category: category}}, _params), do: {category, []}

  defp target(%{assigns: %{source: source} = assigns}, params) do
    category =
      Enum.find(assigns.categories, assigns.category, &(&1.id == params["category_id"]))

    {category, forked_from: source}
  end

  # Shown once "Post topic" was pressed, not while the form is being filled in.
  defp tag_errors(%{source: %{action: :insert}} = form),
    do: Enum.map(form[:tag_ids].errors, &translate_error/1)

  defp tag_errors(_form), do: []

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("New topic")}
        <:subtitle :if={!@source}>
          <.link href={~p"/c/#{@category.slug}"} class="link">{@category.name}</.link>
        </:subtitle>
      </.header>

      <blockquote :if={@source} id="forked-from" class="border-l-2 border-base-300 pl-3 text-sm">
        <.link href={~p"/m/#{@source.id}"} class="link">
          {gettext("From %{name} in “%{topic}”",
            name: @source.author.display_name,
            topic: @source.topic.title
          )}
        </.link>
        <span class="opacity-70">{Forum.excerpt(@source)}</span>
      </blockquote>

      <.form for={@form} id="new-topic-form" phx-change="validate" phx-submit="post">
        <.input
          :if={@source}
          name="topic[category_id]"
          id="topic_category_id"
          type="select"
          label={gettext("Category")}
          options={Enum.map(@categories, &{&1.name, &1.id})}
          value={@form.params["category_id"] || @category.id}
        />
        <.input field={@form[:title]} type="text" label={gettext("Title")} maxlength="150" required />
        <fieldset :if={@tags != []} id="topic-tags">
          <legend class="label mb-1">{gettext("Tags (choose at least one)")}</legend>
          <input type="hidden" name="topic[tag_ids][]" value="" />
          <div class="tag-choices">
            <label :for={tag <- @tags} class="tag-choice">
              <input
                type="checkbox"
                name="topic[tag_ids][]"
                value={tag.id}
                checked={tag.id in List.wrap(@form.params["tag_ids"])}
                class="checkbox checkbox-xs"
              />
              {tag.name}
            </label>
          </div>
          <p
            :for={error <- tag_errors(@form)}
            id="topic-tags-error"
            class="mt-1.5 flex gap-2 items-center text-sm text-error"
          >
            <.icon name="hero-exclamation-circle" class="size-5" />{error}
          </p>
        </fieldset>
        <MessageComponents.editor
          field={@form[:body]}
          label={gettext("First message (Markdown)")}
          mode={@editor_mode}
          preview_html={@preview_html}
          upload={@uploads.editor_image}
          image_error={@image_error}
        />
        <.button class="btn btn-primary">{gettext("Post topic")}</.button>
      </.form>
    </Layouts.app>
    """
  end
end

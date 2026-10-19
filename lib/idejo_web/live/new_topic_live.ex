# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.NewTopicLive do
  @moduledoc """
  New topic (TP-01) at `/c/{slug}/new`: a title and a first message, posted together. Only
  for users with the `:start` right in the category.

  The first message is written in the message editor every message uses (TP-02). Nobody
  else sees it while it is typed: nothing is stored or sent anywhere before "Post topic", and
  the preview is rendered for the author alone. It is then posted closed, with the title.
  """
  use IdejoWeb, :live_view

  alias Idejo.Access
  alias Idejo.Forum

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Forum.get_viewable_category(user, slug) do
      nil ->
        raise Ecto.NoResultsError, queryable: Idejo.Forum.Category

      category ->
        if Access.can?(user, :start, category) do
          {:ok,
           socket
           |> assign(:page_title, gettext("New topic in %{category}", category: category.name))
           |> assign(:category, category)
           |> assign(:form, to_form(Forum.change_new_topic(), as: :topic))
           |> assign(editor_mode: :write, preview_html: "")}
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
    form = params |> Forum.change_new_topic() |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(form, as: :topic))}
  end

  def handle_event("editor_mode", %{"mode" => "preview"}, socket) do
    body = socket.assigns.form.params["body"] || ""

    {:noreply, assign(socket, editor_mode: :preview, preview_html: Idejo.Markdown.to_html(body))}
  end

  def handle_event("editor_mode", %{"mode" => "write"}, socket),
    do: {:noreply, assign(socket, :editor_mode, :write)}

  def handle_event("post", %{"topic" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Forum.create_topic(user, socket.assigns.category, params) do
      {:ok, topic} ->
        {:noreply, redirect(socket, to: ~p"/t/#{topic.id}/#{topic.slug}")}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You cannot start topics in this category."))
         |> redirect(to: ~p"/c/#{socket.assigns.category.slug}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form, as: :topic))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("New topic")}
        <:subtitle>
          <.link href={~p"/c/#{@category.slug}"} class="link">{@category.name}</.link>
        </:subtitle>
      </.header>

      <.form for={@form} id="new-topic-form" phx-change="validate" phx-submit="post">
        <.input field={@form[:title]} type="text" label={gettext("Title")} maxlength="150" required />
        <MessageComponents.editor
          field={@form[:body]}
          label={gettext("First message (Markdown)")}
          mode={@editor_mode}
          preview_html={@preview_html}
        />
        <.button class="btn btn-primary">{gettext("Post topic")}</.button>
      </.form>
    </Layouts.app>
    """
  end
end

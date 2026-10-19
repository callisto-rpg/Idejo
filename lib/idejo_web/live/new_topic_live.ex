# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.NewTopicLive do
  @moduledoc """
  New topic (TP-01) at `/c/{slug}/new`: a title and a first message, posted together. Only
  for users with the `:start` right in the category.
  """
  use IdejoWeb, :live_view

  alias Idejo.Forum

  @impl true
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
           |> assign(:category, category)
           |> assign(:form, to_form(Forum.change_new_topic(), as: :topic))}
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
        <.input
          field={@form[:body]}
          type="textarea"
          label={gettext("First message (Markdown)")}
          rows="10"
          required
        />
        <.button class="btn btn-primary">{gettext("Post topic")}</.button>
      </.form>
    </Layouts.app>
    """
  end
end

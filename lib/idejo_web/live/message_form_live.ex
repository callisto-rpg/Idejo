# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MessageFormLive do
  @moduledoc """
  Posting in a topic, embedded in the server-rendered topic page for signed-in users who may
  post there (TP-08). It writes in the message editor every message uses (TP-02), and posts
  closed until growing messages arrive (M3). With a message to reply to, it shows a short
  excerpt of it, and the reply is posted referencing it.

  The topic page renders it with `live_render/3` and a session of `"topic_id"` and, when the
  reader chose "Reply", `"reply_to_id"`.
  """
  use IdejoWeb, :live_view

  alias Idejo.Forum

  on_mount {IdejoWeb.UserAuth, :require_authenticated}

  @impl true
  def mount(_params, %{"topic_id" => topic_id} = session, socket) do
    user = socket.assigns.current_scope.user
    topic = Forum.get_viewable_topic(user, topic_id)

    {:ok,
     socket
     |> assign(:topic, topic)
     |> assign(:reply_to, topic && Forum.get_topic_message(topic, session["reply_to_id"]))
     |> assign(:form, to_form(Forum.change_new_message(), as: :message))
     |> assign(editor_mode: :write, preview_html: "")}
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    form = params |> Forum.change_new_message() |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(form, as: :message))}
  end

  def handle_event("editor_mode", %{"mode" => "preview"}, socket) do
    body = socket.assigns.form.params["body"] || ""

    {:noreply, assign(socket, editor_mode: :preview, preview_html: Idejo.Markdown.to_html(body))}
  end

  def handle_event("editor_mode", %{"mode" => "write"}, socket),
    do: {:noreply, assign(socket, :editor_mode, :write)}

  def handle_event("cancel_reply", _params, socket),
    do: {:noreply, assign(socket, :reply_to, nil)}

  def handle_event("post", %{"message" => params}, socket) do
    %{topic: topic, reply_to: reply_to} = socket.assigns
    params = Map.put(params, "reply_to_id", reply_to && reply_to.id)

    case Forum.post_message(socket.assigns.current_scope.user, topic, params) do
      {:ok, message} ->
        # The page is server-rendered: load it again, at the new message.
        {:noreply,
         redirect(socket, to: ~p"/t/#{topic.id}/#{topic.slug}" <> "#message-#{message.id}")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot post in this topic."))}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form, as: :message))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="message-form-section" aria-labelledby="message-form-heading">
      <h2 id="message-form-heading" class="font-semibold mb-2">
        {if @reply_to, do: gettext("Reply"), else: gettext("Write a message")}
      </h2>
      <p :if={@flash["error"]} role="alert" class="alert alert-error mb-2">{@flash["error"]}</p>

      <div :if={@reply_to} id="replying-to" class="border-l-2 border-base-300 pl-3 mb-3 text-sm">
        <p>
          {gettext("Replying to %{name}:", name: @reply_to.author.display_name)}
          <button type="button" class="link ml-2" phx-click="cancel_reply">
            {gettext("Cancel reply")}
          </button>
        </p>
        <p class="opacity-70">{Forum.excerpt(@reply_to)}</p>
      </div>

      <.form for={@form} id="message-form" phx-change="validate" phx-submit="post">
        <MessageComponents.editor
          field={@form[:body]}
          label={gettext("Message (Markdown)")}
          mode={@editor_mode}
          preview_html={@preview_html}
        />
        <.button class="btn btn-primary">{gettext("Post")}</.button>
      </.form>
    </section>
    """
  end
end

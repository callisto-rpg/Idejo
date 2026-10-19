# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicLive do
  @moduledoc """
  A topic's messages, live (TP-04), with the message form for those who may post (TP-08).

  The topic page stays a controller (steward decision for M3): it embeds this LiveView with
  `live_render/3` and a session of `"topic_id"` and, after "Reply", `"reply_to_id"`. Its first
  render is the full list in the HTML, so the page reads without JavaScript (AX-04, CL-02).

  Connected, it subscribes to the topic's events before it loads the messages, so nothing
  posted in between is missed. Each `{:message, message}` updates that message in place or
  adds it at the end. A dropped connection reconnects by itself and mounts again, which loads
  the messages afresh: that is the catch-up of anything missed while away.
  """
  use IdejoWeb, :live_view

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Repo

  on_mount {IdejoWeb.UserAuth, :mount_current_scope}

  @impl true
  def mount(_params, %{"topic_id" => topic_id} = session, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user
    # Keeps the anchors permalinks lead to (TP-06): /m/{id} goes to #message-{id}.
    socket = stream_configure(socket, :messages, dom_id: &"message-#{&1.id}")

    case Forum.get_viewable_topic(user, topic_id) do
      nil ->
        {:ok, assign(socket, topic: nil, can_post?: false) |> stream(:messages, [])}

      topic ->
        # First subscribe, then load: a message posted in between arrives as an event.
        if connected?(socket), do: Messages.subscribe(topic.id)
        can_post? = Forum.can_post?(user, topic)

        {:ok,
         socket
         |> assign(topic: topic, can_post?: can_post?)
         |> assign(:reply_to, can_post? && Forum.get_topic_message(topic, session["reply_to_id"]))
         |> assign_form()
         |> stream(:messages, Forum.list_messages(topic))}
    end
  end

  defp assign_form(socket) do
    socket
    |> assign(:form, to_form(Forum.change_new_message(), as: :message))
    |> assign(editor_mode: :write, preview_html: "")
  end

  @impl true
  def handle_info({:message, message}, socket) do
    message = Repo.preload(message, [:author, reply_to: :author])
    {:noreply, stream_insert(socket, :messages, message)}
  end

  # The composer (M3 step 3) uses it; the list has nothing to change.
  def handle_info({:window_ended, _message_id}, socket), do: {:noreply, socket}

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
      # The message itself arrives like everyone else's, as an event.
      {:ok, _message} ->
        {:noreply, socket |> assign(:reply_to, nil) |> assign_form()}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> assign(:can_post?, false)
         |> put_flash(:error, gettext("You cannot post in this topic."))}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form, as: :message))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="topic-live">
      <ol id="messages" class="space-y-6" phx-update="stream">
        <li :for={{dom_id, message} <- @streams.messages} id={dom_id}>
          <.message message={message} topic={@topic} can_post?={@can_post?} />
        </li>
      </ol>

      <div :if={@topic} class="mt-8">
        <p :if={@flash["error"]} role="alert" class="alert alert-error mb-2">{@flash["error"]}</p>
        <%= cond do %>
          <% @can_post? -> %>
            <.message_form
              form={@form}
              reply_to={@reply_to}
              mode={@editor_mode}
              preview_html={@preview_html}
            />
          <% @topic.state != "open" -> %>
            <p id="topic-closed" class="opacity-70">
              {gettext("This topic takes no new messages.")}
            </p>
          <% is_nil(@current_scope) -> %>
            <p id="sign-in-to-post">
              <.link href={~p"/users/sign-in"} class="link">
                {gettext("Sign in to take part.")}
              </.link>
            </p>
          <% true -> %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true
  attr :topic, :map, required: true
  attr :can_post?, :boolean, required: true

  defp message(assigns) do
    ~H"""
    <article aria-labelledby={"message-#{@message.id}-author"}>
      <p class="text-sm">
        <span id={"message-#{@message.id}-author"} class="font-semibold">
          {@message.author.display_name}
        </span>
        <.link
          href={~p"/m/#{@message.id}"}
          class="opacity-70 link link-hover"
          title={gettext("Permalink to this message")}
        >
          <time datetime={DateTime.to_iso8601(@message.opened_at)}>
            {Calendar.strftime(@message.opened_at, "%Y-%m-%d %H:%M UTC")}
          </time>
        </.link>
      </p>
      <blockquote
        :if={@message.reply_to}
        id={"message-#{@message.id}-reply-to"}
        class="border-l-2 border-base-300 pl-3 my-1 text-sm"
      >
        <.link href={~p"/m/#{@message.reply_to.id}"} class="link">
          {gettext("In reply to %{name}", name: @message.reply_to.author.display_name)}
        </.link>
        <span class="opacity-70">{Forum.excerpt(@message.reply_to)}</span>
      </blockquote>
      <MessageComponents.body html={@message.body_html} />
      <.link
        :if={@can_post?}
        href={~p"/t/#{@topic.id}/#{@topic.slug}?reply_to=#{@message.id}" <> "#message-form-section"}
        class="link text-sm"
        aria-label={gettext("Reply to %{name}", name: @message.author.display_name)}
      >
        {gettext("Reply")}
      </.link>
    </article>
    """
  end

  attr :form, :map, required: true
  attr :reply_to, :any, required: true
  attr :mode, :atom, required: true
  attr :preview_html, :string, required: true

  defp message_form(assigns) do
    ~H"""
    <section id="message-form-section" aria-labelledby="message-form-heading">
      <h2 id="message-form-heading" class="font-semibold mb-2">
        {if @reply_to, do: gettext("Reply"), else: gettext("Write a message")}
      </h2>

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
          mode={@mode}
          preview_html={@preview_html}
        />
        <.button class="btn btn-primary">{gettext("Post")}</.button>
      </.form>
    </section>
    """
  end
end

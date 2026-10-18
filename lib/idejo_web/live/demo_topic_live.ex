# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.DemoTopicLive do
  @moduledoc """
  Prototype topic page for trying the composer (dev only, before M3).

  The composer sits in place of the viewer's open message, so replies from
  others appear below it (GM-08). Open `?name=Ana&role=Moderator` in two tabs to
  try it with two people.
  """

  use IdejoWeb, :live_view

  alias Idejo.Messages.DemoTopic

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: DemoTopic.subscribe()

    author = %{
      id: Base.url_encode64(:crypto.strong_rand_bytes(9)),
      name: params["name"] || "Guest #{:rand.uniform(9000) + 999}",
      role: params["role"] || gettext("Member")
    }

    {:ok, assign(socket, author: author, messages: DemoTopic.list())}
  end

  @impl true
  def handle_event("commit", %{"body" => body, "break" => break?}, socket) do
    {:ok, message} = DemoTopic.commit(DemoTopic, socket.assigns.author, body, break: break?)
    {:reply, %{closed: message.state == :closed}, socket}
  end

  @impl true
  def handle_info({:messages, messages}, socket) do
    {:noreply, assign(socket, messages: messages)}
  end

  @impl true
  def render(assigns) do
    {before, mine, rest} = split(assigns.messages, assigns.author.id)
    assigns = assign(assigns, before: before, mine: mine, rest: rest)

    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-xl font-semibold">{gettext("Composer prototype")}</h1>
      <div id="topic" class="flex flex-col gap-4">
        <div id="before" class="flex flex-col gap-4">
          <.message :for={m <- @before} message={m} />
        </div>
        <div id="composer-slot" class="flex flex-col gap-1">
          <.author_line :if={@mine} author={@author} />
          <div id="composer" class="composer" phx-hook="Composer" phx-update="ignore">
            <div class="composer-backdrop" aria-hidden="true"></div>
            <textarea
              class="composer-input"
              rows="1"
              aria-label={gettext("Message")}
              placeholder={
                gettext("Type here · Enter send · Shift+Enter line break · Ctrl+Enter new line")
              }
            ></textarea>
          </div>
        </div>
        <div id="after" class="flex flex-col gap-4">
          <.message :for={m <- @rest} message={m} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Messages before the viewer's open message, that message, and the ones after.
  # With no open message the composer goes to the end of the topic.
  defp split(messages, author_id) do
    case Enum.split_while(messages, &(not (&1.state == :open and &1.author.id == author_id))) do
      {before, [mine | rest]} -> {before, mine, rest}
      {all, []} -> {all, nil, []}
    end
  end

  attr :message, :map, required: true

  defp message(assigns) do
    ~H"""
    <article id={"m#{@message.id}"} class="flex flex-col gap-1">
      <.author_line author={@message.author} />
      <p class="whitespace-pre-wrap break-words pl-11">
        {@message.body}<span :if={@message.state == :open} class="sr-only">{gettext(
          "(still being written)"
        )}</span>
      </p>
    </article>
    """
  end

  attr :author, :map, required: true

  defp author_line(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span
        class="flex size-8 shrink-0 items-center justify-center rounded-full bg-neutral text-xs text-neutral-content"
        aria-hidden="true"
      >
        {initials(@author.name)}
      </span>
      <span class="font-semibold">{@author.name}</span>
      <span class="text-xs opacity-60">{@author.role}</span>
    </div>
    """
  end

  defp initials(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end
end

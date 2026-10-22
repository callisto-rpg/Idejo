# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MessageModerationComponents do
  @moduledoc """
  A moderator's tools on a topic's messages, in `IdejoWeb.TopicLive` (steward decision,
  2026-10-23):

    * `moderate_card/1`: a message's "Moderate", as a card over the page: close an open
      message (GM-16), delete it (MO-02), or "Select to be moved" (TP-15).
    * `move_banner/1`: while selecting, a banner at the top, "Move all selected messages to"
      a new thread or an existing one.
    * `move_dialog/1`: the new thread's title and category, or a search for the existing one.

  The dialogs use the `InlineCard` hook, with their own close event.
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext

  import IdejoWeb.CoreComponents, only: [icon: 1]

  attr :message, :map, required: true
  attr :own?, :boolean, required: true, doc: "the moderator's own message: no close or delete"
  attr :movable?, :boolean, required: true, doc: "false for the topic's opening message"

  def moderate_card(assigns) do
    ~H"""
    <dialog
      id="moderate-card"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="close_moderate"
      aria-labelledby="moderate-card-title"
    >
      <div class="modal-box inline-card">
        <h2 id="moderate-card-title" class="inline-card-title">
          <.icon name="hero-shield-check" class="size-5" />
          {gettext("Moderate the message by %{name}", name: @message.author.display_name)}
        </h2>
        <form
          :if={!@own? and is_nil(@message.deleted_at)}
          phx-submit="moderate_message"
          id={"message-#{@message.id}-moderate-form"}
          class="grid gap-2"
        >
          <input type="hidden" name="message_id" value={@message.id} />
          <label>
            <span class="label mb-1">{gettext("Reason (shown in the moderation log)")}</span>
            <input type="text" name="reason" maxlength="500" class="input input-sm w-full" />
          </label>
          <div class="inline-card-actions">
            <button
              :if={@message.state == "open"}
              name="do"
              value="close"
              class="btn btn-sm"
              data-confirm={gettext("Close this message? Its author will start a new one.")}
            >
              {gettext("Close message")}
            </button>
            <button
              name="do"
              value="delete"
              class="btn btn-sm btn-error"
              data-confirm={
                gettext("Delete this message? Readers will see that a moderator deleted it.")
              }
            >
              {gettext("Delete message")}
            </button>
          </div>
        </form>
        <div :if={@movable?} class="moderate-card-move">
          <button
            type="button"
            class="btn btn-sm"
            phx-click="start_selecting"
            phx-value-id={@message.id}
          >
            <.icon name="hero-check-circle" class="size-4" />{gettext("Select to be moved")}
          </button>
          <p class="inline-card-meta">
            {gettext("Choose messages of this thread, then move them to a new or existing thread.")}
          </p>
        </div>
        <p :if={!@movable?} class="inline-card-meta">
          {gettext("The opening message stays with its thread; move the whole thread instead.")}
        </p>
        <div class="modal-action">
          <button type="button" class="btn btn-sm btn-ghost" phx-click="close_moderate">
            {gettext("Close")}
          </button>
        </div>
      </div>
    </dialog>
    """
  end

  attr :count, :integer, required: true

  def move_banner(assigns) do
    ~H"""
    <section id="move-banner" class="move-banner" aria-labelledby="move-banner-title">
      <p id="move-banner-title" class="move-banner-title">
        {gettext("Move all selected messages to")}
      </p>
      <p class="move-banner-count" role="status">
        {ngettext("1 message selected", "%{count} messages selected", @count)}
      </p>
      <div class="move-banner-actions">
        <button
          type="button"
          class="btn btn-sm btn-primary"
          phx-click="move_to"
          phx-value-to="new"
          disabled={@count == 0}
        >
          {gettext("New thread")}
        </button>
        <button
          type="button"
          class="btn btn-sm btn-primary"
          phx-click="move_to"
          phx-value-to="existing"
          disabled={@count == 0}
        >
          {gettext("Existing thread")}
        </button>
        <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel_selecting">
          {gettext("Cancel")}
        </button>
      </div>
    </section>
    """
  end

  attr :to, :atom, values: [:new, :existing], required: true
  attr :count, :integer, required: true
  attr :categories, :list, default: [], doc: "for a new thread"
  attr :current_category_id, :string, default: nil
  attr :query, :string, default: ""
  attr :results, :list, default: [], doc: "for an existing thread"
  attr :error, :string, default: nil

  def move_dialog(assigns) do
    ~H"""
    <dialog
      id="move-dialog"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="close_move"
      aria-labelledby="move-dialog-title"
    >
      <div class="modal-box inline-card move-dialog">
        <h2 id="move-dialog-title" class="inline-card-title">
          {if @to == :new,
            do:
              ngettext(
                "Move 1 message to a new thread",
                "Move %{count} messages to a new thread",
                @count
              ),
            else:
              ngettext(
                "Move 1 message to an existing thread",
                "Move %{count} messages to an existing thread",
                @count
              )}
        </h2>
        <p :if={@error} role="alert" class="text-sm text-error">{@error}</p>

        <form :if={@to == :new} id="move-new-form" phx-submit="move_selected" class="grid gap-2">
          <input type="hidden" name="to" value="new" />
          <label>
            <span class="label mb-1">{gettext("Title of the new thread")}</span>
            <input type="text" name="title" maxlength="150" required class="input input-sm w-full" />
          </label>
          <label>
            <span class="label mb-1">{gettext("Category")}</span>
            <select name="category_id" class="select select-sm w-full">
              <option
                :for={category <- @categories}
                value={category.id}
                selected={category.id == @current_category_id}
              >
                {category.name}
              </option>
            </select>
          </label>
          <.reason />
          <div class="inline-card-actions">
            <button class="btn btn-sm btn-primary">{gettext("Move to the new thread")}</button>
          </div>
        </form>

        <form
          :if={@to == :existing}
          id="move-existing-form"
          phx-change="search_targets"
          phx-submit="move_selected"
          class="grid gap-2"
        >
          <input type="hidden" name="to" value="existing" />
          <label>
            <span class="label mb-1">{gettext("Find a thread (title, or paste its link)")}</span>
            <input
              type="search"
              name="q"
              value={@query}
              phx-debounce="200"
              autocomplete="off"
              class="input input-sm w-full"
            />
          </label>
          <fieldset>
            <legend class="sr-only">{gettext("Thread")}</legend>
            <p :if={@results == []} class="inline-card-meta">{gettext("No thread found.")}</p>
            <div class="move-results">
              <label :for={topic <- @results} class="move-result">
                <input type="radio" name="topic_id" value={topic.id} required />
                <span class="move-result-title">{topic.title}</span>
                <span class="inline-card-meta">{topic.category.name}</span>
              </label>
            </div>
          </fieldset>
          <.reason />
          <div class="inline-card-actions">
            <button class="btn btn-sm btn-primary">{gettext("Move to this thread")}</button>
          </div>
        </form>

        <div class="modal-action">
          <button type="button" class="btn btn-sm btn-ghost" phx-click="close_move">
            {gettext("Cancel")}
          </button>
        </div>
      </div>
    </dialog>
    """
  end

  defp reason(assigns) do
    ~H"""
    <label>
      <span class="label mb-1">{gettext("Reason (shown in the moderation log)")}</span>
      <input type="text" name="reason" maxlength="500" class="input input-sm w-full" />
    </label>
    """
  end
end

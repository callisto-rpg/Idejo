# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PollComponents do
  @moduledoc """
  Polls (`!poll`, steward decision, 2026-10-23; `Idejo.Messages.Polls`): the poll under a
  message, and the dialog that adds one.
  """
  use IdejoWeb, :html

  alias Idejo.Messages.{Polls, Scheduling}

  attr :poll, :map, required: true, doc: "a `Idejo.Messages.Polls.summary/1`"
  attr :message, :map, required: true
  attr :viewer, :any, required: true
  attr :can_vote?, :boolean, required: true
  attr :now, DateTime, required: true

  @doc """
  A poll: its question as the legend of its answers, a radio button or checkbox each, and
  Vote. The counts show once the viewer voted (or wrote it), and to everyone once it closed.
  """
  def poll(assigns) do
    %{poll: poll, viewer: viewer} = assigns
    open? = Polls.open?(poll, assigns.now)
    mine = (viewer && Map.get(poll.votes, viewer.id)) || []

    assigns =
      assign(assigns,
        id: "poll-#{assigns.message.id}",
        open?: open?,
        mine: mine,
        voting?: open? and assigns.can_vote? and viewer != nil,
        results?: Polls.results_shown?(poll, viewer, assigns.message, assigns.now)
      )

    ~H"""
    <.form for={%{}} id={@id} class="poll" phx-submit="vote">
      <input type="hidden" name="message_id" value={@message.id} />
      <fieldset disabled={!@voting?}>
        <legend id={"#{@id}-question"} class="poll-question">{@poll.question}</legend>
        <div :for={option <- @poll.options} class="poll-option">
          <label class="poll-answer">
            <input
              type={if @poll.multiple, do: "checkbox", else: "radio"}
              class={if @poll.multiple, do: "checkbox checkbox-sm", else: "radio radio-sm"}
              name="options[]"
              value={option.id}
              checked={option.id in @mine}
            />
            <span>{option.text}</span>
            <span :if={@results?} class="poll-count">
              {ngettext("%{count} vote", "%{count} votes", option.count)} ({percent(
                option.count,
                @poll.voters
              )}%)
            </span>
          </label>
          <progress
            :if={@results?}
            class="poll-bar"
            value={option.count}
            max={max(@poll.voters, 1)}
            aria-hidden="true"
          ></progress>
        </div>
      </fieldset>
      <p class="poll-meta">
        <span :if={@poll.multiple}>{gettext("Choose any number of answers.")}</span>
        <span>{ngettext("%{count} voter", "%{count} voters", @poll.voters)}</span>
        <span :if={@open?}>
          {gettext("Closes")}
          <time datetime={DateTime.to_iso8601(@poll.closes_at)}>
            {Calendar.strftime(@poll.closes_at, "%Y-%m-%d %H:%M UTC")}
          </time>
        </span>
        <span :if={!@open?} class="poll-closed">{gettext("Closed")}</span>
        <span :if={@open? and !@results?}>{gettext("Results show once you vote.")}</span>
      </p>
      <button :if={@voting?} class="btn btn-xs">
        {if @mine == [], do: gettext("Vote"), else: gettext("Change vote")}
      </button>
    </.form>
    """
  end

  defp percent(_count, 0), do: 0
  defp percent(count, voters), do: round(count * 100 / voters)

  attr :form, :map, required: true, doc: "`message_id`, `params`, `count` of answers, `error`"

  @doc """
  The dialog `!poll` opens: the question, the answers (two to start with, Add an answer for
  more), whether several may be chosen and the hours until it closes. The InlineCard hook
  opens it as a modal dialog and reports its closing.
  """
  def poll_dialog(assigns) do
    params = assigns.form.params
    options = List.wrap(params["options"])

    assigns =
      assign(assigns,
        question: params["question"],
        options: for(i <- 0..(assigns.form.count - 1), do: Enum.at(options, i)),
        multiple?: params["multiple"] == "true",
        hours: params["hours"],
        max_hours: Scheduling.max_hours(),
        more?: assigns.form.count < Polls.max_options()
      )

    ~H"""
    <dialog
      id="poll-dialog"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="hide_poll"
      aria-labelledby="poll-dialog-title"
    >
      <div class="modal-box poll-card">
        <h2 id="poll-dialog-title" class="inline-card-title">{gettext("Add a poll")}</h2>
        <.form for={%{}} id="poll-form" phx-change="poll_change" phx-submit="create_poll">
          <label for="poll-question" class="label mb-1">{gettext("Question")}</label>
          <input
            id="poll-question"
            name="poll[question]"
            type="text"
            value={@question}
            required
            class="input input-sm w-full"
            phx-mounted={JS.focus()}
          />
          <fieldset class="poll-card-answers">
            <legend class="label mb-1">{gettext("Answers")}</legend>
            <input
              :for={{value, i} <- Enum.with_index(@options)}
              id={"poll-option-#{i}"}
              name="poll[options][]"
              type="text"
              value={value}
              aria-label={gettext("Answer %{number}", number: i + 1)}
              class="input input-sm w-full"
            />
            <button
              :if={@more?}
              type="button"
              id="poll-add-option"
              class="btn btn-xs btn-ghost"
              phx-click="poll_add_option"
            >
              <.icon name="hero-plus-micro" class="size-4" />{gettext("Add an answer")}
            </button>
          </fieldset>
          <label class="label poll-card-multiple">
            <input type="hidden" name="poll[multiple]" value="false" />
            <input
              id="poll-multiple"
              name="poll[multiple]"
              type="checkbox"
              value="true"
              checked={@multiple?}
              class="toggle toggle-sm"
            />
            {gettext("Allow several answers")}
          </label>
          <label for="poll-hours" class="label mb-1">
            {gettext("Close it in how many hours? (at most %{max})", max: @max_hours)}
          </label>
          <input
            id="poll-hours"
            name="poll[hours]"
            type="number"
            inputmode="decimal"
            min="0.01"
            max={@max_hours}
            step="any"
            value={@hours}
            required
            class="input input-sm w-full"
          />
          <p :if={@form.error} id="poll-error" role="alert" class="text-sm text-error mt-1">
            {@form.error}
          </p>
          <div class="modal-action">
            <button class="btn btn-sm btn-primary">{gettext("Add poll")}</button>
            <button type="button" class="btn btn-sm btn-ghost" phx-click="hide_poll">
              {gettext("Cancel")}
            </button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PollComponents do
  @moduledoc """
  Polls (`!poll`, steward decision, 2026-10-23; `Idejo.Messages.Polls`): the poll under a
  message, and the dialog that adds one. Since the steward decision of 2026-11-02 the
  answers stand side by side, each over a thick vertical bar in its colour (the theme's
  without one) with its emoji, and the fields (`poll_fields/1`) are shared with **Admin →
  Automessages**, whose automessages may post a poll.
  """
  use IdejoWeb, :html

  alias Idejo.Emoji
  alias Idejo.Messages.{Polls, Scheduling}
  alias IdejoWeb.ReactionComponents

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
    <%!-- Narrow screens (steward decision, 2026-11-02): the columns shrink to stay on one
         line (CSS); when an answer's text no longer fits its column, the `PollLayout` hook
         sets data-layout="list": bars, counts and emojis stay columns, and each answer is a
         row under them, its button, emoji and text. --%>
    <.form
      for={%{}}
      id={@id}
      class="poll"
      phx-submit="vote"
      phx-hook="PollLayout"
      phx-mounted={JS.ignore_attributes(["data-layout", "data-measuring"])}
    >
      <input type="hidden" name="message_id" value={@message.id} />
      <fieldset disabled={!@voting?}>
        <legend id={"#{@id}-question"} class="poll-question">{@poll.question}</legend>
        <div class={["poll-options", "poll-options-n#{length(@poll.options)}"]}>
          <label :for={option <- @poll.options} class="poll-option">
            <%!-- The bar: an SVG whose height and fill are attributes, never a style
                 (SP-05); without a colour of its own, the theme's (.is-theme). --%>
            <svg
              :if={@results?}
              class="poll-bar"
              viewBox="0 0 10 100"
              preserveAspectRatio="none"
              aria-hidden="true"
            >
              <rect class="poll-bar-track" width="10" height="100" />
              <rect
                :if={option.count > 0}
                class={["poll-bar-fill", is_nil(option.colour) && "is-theme"]}
                y={100 - share(option.count, @poll.voters)}
                width="10"
                height={share(option.count, @poll.voters)}
                fill={option.colour}
              />
            </svg>
            <span :if={@results?} class="poll-count">
              {ngettext("%{count} vote", "%{count} votes", option.count)}
              <span class="poll-percent">{percent(option.count, @poll.voters)}%</span>
            </span>
            <ReactionComponents.emoji_img
              :if={emoji(option)}
              emoji={emoji(option)}
              class="emoji poll-emoji"
            />
            <%!-- The answer: under its column, or a row of its own in the list layout, where
                 its emoji is drawn again beside it (decorative there: alt=""). --%>
            <span class="poll-choice">
              <input
                type={if @poll.multiple, do: "checkbox", else: "radio"}
                class={if @poll.multiple, do: "checkbox checkbox-sm", else: "radio radio-sm"}
                name="options[]"
                value={option.id}
                checked={option.id in @mine}
              />
              <img
                :if={emoji(option)}
                src={emoji(option).src}
                alt=""
                class="emoji poll-emoji-inline"
                loading="lazy"
              />
              <span class="poll-answer-text">{option.text}</span>
            </span>
          </label>
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
        <span :if={@open? and !@results? and Map.get(@poll, :hide_results)}>
          {gettext("Results show when the poll closes.")}
        </span>
        <span :if={@open? and !@results? and !Map.get(@poll, :hide_results)}>
          {gettext("Results show once you vote.")}
        </span>
      </p>
      <button :if={@voting?} class="btn btn-xs">
        {if @mine == [], do: gettext("Vote"), else: gettext("Change vote")}
      </button>
    </.form>
    """
  end

  defp emoji(%{emoji: name}) when is_binary(name), do: Emoji.lookup(name)
  defp emoji(_option), do: nil

  # The bar's height, out of 100.
  defp share(_count, 0), do: 0
  defp share(count, voters), do: count * 100 / voters

  defp percent(_count, 0), do: 0
  defp percent(count, voters), do: round(count * 100 / voters)

  attr :form, :map, required: true, doc: "`message_id`, `params`, `count` of answers, `error`"

  @doc """
  The dialog `!poll` opens, around `poll_fields/1`. The InlineCard hook opens it as a modal
  dialog and reports its closing.
  """
  def poll_dialog(assigns) do
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
          <.poll_fields name="poll" id="poll" params={@form.params} count={@form.count} />
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

  attr :name, :string, required: true, doc: "the fields' name prefix, e.g. `poll`"
  attr :id, :string, required: true, doc: "the fields' id prefix"
  attr :params, :map, required: true, doc: "what the form holds"
  attr :count, :integer, required: true, doc: "how many answers to show"

  @doc """
  A poll's fields: the question; the answers (two to start with, Add an answer for more),
  each with an emoji button (the emoji picker, `"emoji_picker"` with `poll_option`, then
  `"poll_emoji"`; × takes it back, `"poll_emoji_clear"`) and a bar colour (the theme's to
  start with); whether several may be chosen; whether the results stay hidden until it
  closes; the hours until it closes. Sent as `name[question]`, `name[options][]`,
  `name[emojis][]`, `name[colours][]`, `name[multiple]`, `name[hide_results]`,
  `name[hours]`, which `Idejo.Messages.Polls.validate/1` reads. The LiveView handles
  `"poll_add_option"` too.
  """
  def poll_fields(assigns) do
    params = assigns.params
    options = List.wrap(params["options"])
    emojis = List.wrap(params["emojis"])
    colours = List.wrap(params["colours"])
    default = Polls.default_colour()

    assigns =
      assign(assigns,
        question: params["question"],
        rows:
          for i <- 0..(assigns.count - 1) do
            emoji = Enum.at(emojis, i)

            %{
              index: i,
              text: Enum.at(options, i),
              emoji: emoji,
              shown: is_binary(emoji) && Emoji.lookup(emoji),
              colour: colour(Enum.at(colours, i), default)
            }
          end,
        multiple?: params["multiple"] in [true, "true"],
        hidden?: params["hide_results"] in [true, "true"],
        hours: params["hours"],
        max_hours: Scheduling.max_hours(),
        more?: assigns.count < Polls.max_options()
      )

    ~H"""
    <div class="poll-fields">
      <label for={"#{@id}-question"} class="label mb-1">{gettext("Question")}</label>
      <input
        id={"#{@id}-question"}
        name={"#{@name}[question]"}
        type="text"
        value={@question}
        required
        class="input input-sm w-full"
        phx-mounted={JS.focus()}
      />
      <fieldset class="poll-card-answers">
        <legend class="label mb-1">{gettext("Answers")}</legend>
        <div :for={row <- @rows} class="poll-card-answer">
          <input type="hidden" name={"#{@name}[emojis][]"} value={row.emoji || ""} />
          <span class="poll-card-emoji-wrap">
            <button
              type="button"
              id={"#{@id}-emoji-#{row.index}"}
              class="btn btn-sm btn-ghost btn-square poll-card-emoji"
              phx-click="emoji_picker"
              phx-value-poll_option={row.index}
              aria-label={
                if row.shown,
                  do:
                    gettext("Emoji of answer %{number}: :%{name}:. Change it",
                      number: row.index + 1,
                      name: row.emoji
                    ),
                  else: gettext("Choose an emoji for answer %{number}", number: row.index + 1)
              }
            >
              <ReactionComponents.emoji_img :if={row.shown} emoji={row.shown} />
              <.icon :if={!row.shown} name="hero-face-smile" class="size-5" />
            </button>
            <button
              :if={row.shown}
              type="button"
              class="btn btn-xs btn-ghost btn-square poll-card-emoji-clear"
              phx-click="poll_emoji_clear"
              phx-value-index={row.index}
              aria-label={gettext("Remove the emoji of answer %{number}", number: row.index + 1)}
            >
              <.icon name="hero-x-mark-micro" class="size-4" />
            </button>
          </span>
          <input
            id={"#{@id}-option-#{row.index}"}
            name={"#{@name}[options][]"}
            type="text"
            value={row.text}
            aria-label={gettext("Answer %{number}", number: row.index + 1)}
            class="input input-sm flex-1 min-w-0"
          />
          <input
            id={"#{@id}-colour-#{row.index}"}
            name={"#{@name}[colours][]"}
            type="color"
            value={row.colour}
            aria-label={gettext("Bar colour of answer %{number}", number: row.index + 1)}
            class="poll-card-colour"
          />
        </div>
        <button
          :if={@more?}
          type="button"
          id={"#{@id}-add-option"}
          class="btn btn-xs btn-ghost"
          phx-click="poll_add_option"
        >
          <.icon name="hero-plus-micro" class="size-4" />{gettext("Add an answer")}
        </button>
      </fieldset>
      <label class="label poll-card-multiple">
        <input type="hidden" name={"#{@name}[multiple]"} value="false" />
        <input
          id={"#{@id}-multiple"}
          name={"#{@name}[multiple]"}
          type="checkbox"
          value="true"
          checked={@multiple?}
          class="toggle toggle-sm"
        />
        {gettext("Allow several answers")}
      </label>
      <label class="label poll-card-multiple">
        <input type="hidden" name={"#{@name}[hide_results]"} value="false" />
        <input
          id={"#{@id}-hide-results"}
          name={"#{@name}[hide_results]"}
          type="checkbox"
          value="true"
          checked={@hidden?}
          class="toggle toggle-sm"
        />
        {gettext("Hide the results until the poll closes")}
      </label>
      <label for={"#{@id}-hours"} class="label mb-1">
        {gettext("Close it in how many hours? (at most %{max})", max: @max_hours)}
      </label>
      <input
        id={"#{@id}-hours"}
        name={"#{@name}[hours]"}
        type="number"
        inputmode="decimal"
        min="0.01"
        max={@max_hours}
        step="any"
        value={@hours}
        required
        class="input input-sm w-full"
      />
    </div>
    """
  end

  # What the colour picker shows: the answer's colour, else the theme's.
  defp colour(colour, default) when is_binary(colour) do
    if colour =~ ~r/^#[0-9a-fA-F]{6}$/, do: String.downcase(colour), else: default
  end

  defp colour(_colour, default), do: default

  @doc "The form's params with answer `index`'s emoji set to `emoji` (nil: none)."
  @spec put_emoji(map(), non_neg_integer(), String.t() | nil) :: map()
  def put_emoji(params, index, emoji) do
    emojis = List.wrap(params["emojis"])
    padded = emojis ++ List.duplicate("", max(index + 1 - length(emojis), 0))
    Map.put(params, "emojis", List.replace_at(padded, index, emoji || ""))
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.WarningComponents do
  @moduledoc """
  Warnings (MO-02 "warn"; steward request, 2026-11-09; `Idejo.Moderation.Warnings`): the
  card a moderator warns from (`warn_card/1`, from a message's "Warn user") and the card the
  warned member sees until they acknowledge it (`warned_card/1`, `IdejoWeb.NotifierLive`).
  """
  use IdejoWeb, :html

  alias Idejo.Moderation.Warnings

  attr :form, :map,
    required: true,
    doc: "%{user, count, previous (nil until asked), reason, error}"

  @doc ~s|A reason, then "View N previous warnings" and "Warn".|
  def warn_card(assigns) do
    assigns = assign(assigns, :max, Warnings.max_reason())

    ~H"""
    <dialog
      id="warn-dialog"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="close_warn"
      data-return-focus
      aria-labelledby="warn-dialog-title"
    >
      <div class="modal-box warn-card">
        <h2 id="warn-dialog-title" class="inline-card-title">
          {gettext("Warn %{name}", name: @form.user.display_name)}
        </h2>
        <.form for={%{}} as={:warning} id="warn-form" phx-change="warn_change" phx-submit="warn">
          <label for="warn-reason" class="label mb-1">
            {gettext("Reason (the member reads it)")}
          </label>
          <textarea
            id="warn-reason"
            name="warning[reason]"
            rows="4"
            maxlength={@max}
            required
            class="textarea textarea-sm w-full"
            aria-describedby={@form.error && "warn-error"}
            phx-mounted={JS.focus()}
          >{@form.reason}</textarea>
          <p :if={@form.error} id="warn-error" role="alert" class="text-sm text-error mt-1">
            {@form.error}
          </p>
          <section
            :if={@form.previous}
            id="warn-previous"
            aria-labelledby="warn-previous-title"
            class="warn-previous"
          >
            <h3 id="warn-previous-title" class="font-semibold text-sm">
              {gettext("Previous warnings")}
            </h3>
            <p :if={@form.previous == []} class="text-sm">{gettext("None you may see.")}</p>
            <ol :if={@form.previous != []}>
              <li :for={warning <- @form.previous} id={"warning-#{warning.id}"}>
                <p class="warn-previous-meta">
                  <time datetime={DateTime.to_iso8601(warning.created_at)}>
                    {Calendar.strftime(warning.created_at, "%Y-%m-%d %H:%M UTC")}
                  </time>
                  · {(warning.moderator && warning.moderator.display_name) ||
                    gettext("a former moderator")}
                  <a :if={warning.message_id} href={~p"/m/#{warning.message_id}"}>
                    {gettext("the message")}
                  </a>
                </p>
                <p class="warn-previous-reason">{warning.reason}</p>
              </li>
            </ol>
          </section>
          <div class="modal-action warn-actions">
            <button
              :if={!@form.previous}
              type="button"
              id="warn-history"
              class="btn btn-sm btn-ghost"
              phx-click="warn_history"
            >
              {ngettext(
                "View %{count} previous warning",
                "View %{count} previous warnings",
                @form.count
              )}
            </button>
            <span class="flex-1"></span>
            <button type="button" class="btn btn-sm btn-ghost" phx-click="close_warn">
              {gettext("Cancel")}
            </button>
            <button id="warn-submit" class="btn btn-sm btn-warning">{gettext("Warn")}</button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end

  attr :warnings, :list, required: true
  attr :live?, :boolean, required: true
  attr :csrf_token, :string, default: nil

  @doc """
  The warnings waiting for the member, oldest first, with "I understand". Rendered open (a
  form posting to `/warnings/seen` without JavaScript); once connected, a modal
  (`InlineCard`), closing it acknowledges them too.
  """
  def warned_card(assigns) do
    ~H"""
    <dialog
      id="warning-card"
      class="modal"
      open={!@live?}
      phx-hook={@live? && "InlineCard"}
      data-close-event="warnings_seen"
      role="alertdialog"
      aria-labelledby="warning-card-title"
      aria-describedby="warning-card-list"
    >
      <div class="modal-box warning-card">
        <h2 id="warning-card-title" class="inline-card-title">
          <.icon name="hero-exclamation-triangle" class="size-6 text-warning" />
          {ngettext("A moderator warned you", "Moderators warned you", length(@warnings))}
        </h2>
        <ol id="warning-card-list" class="warning-card-list">
          <li :for={warning <- @warnings} id={"warned-#{warning.id}"}>
            <p class="warning-card-reason">{warning.reason}</p>
            <p class="warning-card-meta">
              <time datetime={DateTime.to_iso8601(warning.created_at)}>
                {Calendar.strftime(warning.created_at, "%Y-%m-%d %H:%M UTC")}
              </time>
              <a :if={warning.message_id} href={~p"/m/#{warning.message_id}"}>
                {gettext("The message")}
              </a>
            </p>
          </li>
        </ol>
        <p class="text-sm">{gettext("Please follow the forum's rules.")}
          <a href={~p"/rules"}>{gettext("Read the rules")}</a></p>
        <form
          method="post"
          action={~p"/warnings/seen"}
          phx-submit="warnings_seen"
          class="modal-action"
        >
          <input :if={@csrf_token} type="hidden" name="_csrf_token" value={@csrf_token} />
          <button id="warning-card-ok" class="btn btn-sm btn-primary" phx-mounted={JS.focus()}>
            {gettext("I understand")}
          </button>
        </form>
      </div>
    </dialog>
    """
  end
end

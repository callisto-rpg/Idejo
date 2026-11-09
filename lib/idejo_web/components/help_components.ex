# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.HelpComponents do
  @moduledoc """
  Parts of the Help page that show elsewhere too: "Sending", the keys that send, on `/help`
  and, shortened (`brief`), in the getting-started card (`IdejoWeb.Layouts`; steward
  requests, 2026-11-09).
  """
  use IdejoWeb, :html

  attr :id, :string, required: true, doc: "prefix of the ids, unique on the page"
  attr :heading, :string, values: ~w(h2 h3), default: "h2"
  attr :class, :string, default: nil

  attr :brief, :boolean,
    default: false,
    doc: "the getting-started card's version: no intro line, no Shift+Enter, no delay note"

  @doc "The keys that send: Enter, Shift+Enter and Ctrl+Enter (or Enter three times)."
  def sending(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-title"} class={@class}>
      <.dynamic_tag tag_name={@heading} id={"#{@id}-title"}>{gettext("Sending")}</.dynamic_tag>
      <p :if={!@brief}>
        {gettext(
          "What you send with Enter joins one growing message, live for everyone, until you start a new one."
        )}
      </p>
      <dl class="help-list">
        <div>
          <dt><kbd>Enter</kbd></dt>
          <dd>
            {gettext(
              "Sends what you wrote. Keep typing and press Enter again: it joins the same message."
            )}
          </dd>
        </div>
        <div :if={!@brief}>
          <dt><kbd>Shift</kbd>+<kbd>Enter</kbd></dt>
          <dd>{gettext("A new line in the box. Nothing is sent.")}</dd>
        </div>
        <div>
          <dt>
            <kbd>Ctrl</kbd>+<kbd>Enter</kbd>
            {gettext("or")}
            <kbd>Enter</kbd> ×3
          </dt>
          <dd :if={@brief}>{gettext("Finishes your current message and starts a new one.")}</dd>
          <dd :if={!@brief}>
            {gettext(
              "Finishes your current message and starts a new one. If nobody has replied to your message yet, there will be a longer delay before you are allowed to create a new message."
            )}
          </dd>
        </div>
      </dl>
    </section>
    """
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.MessageComponents do
  @moduledoc """
  The message editor and message bodies, shared by every place a message is written or
  shown (TP-02): the new topic's first message now, replies and the composer later.
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext

  import IdejoWeb.CoreComponents, only: [input: 1]

  @doc """
  A message's body: HTML sanitised by `Idejo.Markdown` before it was stored or previewed
  (FD-03), so it is shown as is. This is the one place message HTML is output raw.
  """
  attr :html, :string, required: true
  attr :rest, :global

  # sobelow_skip ["XSS.Raw"]
  def body(assigns) do
    ~H"""
    <div class="message-body" {@rest}>{Phoenix.HTML.raw(@html)}</div>
    """
  end

  @doc """
  The message editor (TP-02): a Markdown text box with a Write / Preview switch.

  Nothing typed here leaves the author's page until the form is submitted: the preview is
  rendered for them alone. The LiveView handles `"editor_mode"` with `%{"mode" =>
  "write" | "preview"}` and passes the preview's HTML (`Idejo.Markdown.to_html/1`).
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :mode, :atom, values: [:write, :preview], default: :write
  attr :preview_html, :string, default: ""

  def editor(assigns) do
    ~H"""
    <div id={"#{@field.id}-editor"} class="message-editor">
      <div role="tablist" aria-label={@label} class="tabs tabs-border mb-2">
        <button
          type="button"
          role="tab"
          id={"#{@field.id}-write-tab"}
          class={["tab", @mode == :write && "tab-active"]}
          aria-selected={to_string(@mode == :write)}
          phx-click="editor_mode"
          phx-value-mode="write"
        >
          {gettext("Write")}
        </button>
        <button
          type="button"
          role="tab"
          id={"#{@field.id}-preview-tab"}
          class={["tab", @mode == :preview && "tab-active"]}
          aria-selected={to_string(@mode == :preview)}
          phx-click="editor_mode"
          phx-value-mode="preview"
        >
          {gettext("Preview")}
        </button>
      </div>
      <%!-- Kept in the form while previewing, so the text is still posted. --%>
      <div hidden={@mode == :preview}>
        <.input field={@field} type="textarea" label={@label} rows="10" />
      </div>
      <div :if={@mode == :preview} id={"#{@field.id}-preview"} role="tabpanel">
        <p :if={String.trim(@preview_html) == ""} class="opacity-70">
          {gettext("Nothing to preview yet.")}
        </p>
        <.body :if={String.trim(@preview_html) != ""} html={@preview_html} />
      </div>
    </div>
    """
  end
end

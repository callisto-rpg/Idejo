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

  alias Phoenix.LiveView.JS

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
  A message's body in a topic, with no size limit (GM-06). The `ShowAll` hook
  (`assets/js/show_all.js`) collapses a body taller than the screen and shows the "Show all"
  button; it keeps that state in `data-collapsed` / `data-expanded`, which patches leave alone.
  Without JavaScript the whole body is shown and the button stays hidden.
  """
  attr :id, :string, required: true
  attr :html, :string, required: true

  def collapsible_body(assigns) do
    ~H"""
    <div
      id={@id}
      class="message-collapsible"
      phx-hook="ShowAll"
      phx-mounted={JS.ignore_attributes(["data-collapsed", "data-expanded"])}
    >
      <.body id={"#{@id}-text"} html={@html} tabindex="-1" />
      <button
        type="button"
        class="show-all link text-sm"
        aria-controls={"#{@id}-text"}
        aria-expanded="false"
      >
        {gettext("Show all")}
      </button>
    </div>
    """
  end

  @doc """
  The message editor (TP-02): a Markdown text box with a Write / Preview switch.

  Nothing typed here leaves the author's page until the form is submitted: the preview is
  rendered for them alone. The LiveView handles `"editor_mode"` with `%{"mode" =>
  "write" | "preview"}` and passes the preview's HTML (`Idejo.Messages.Body.to_html/1`).

  With `upload` (an image upload allowed with `IdejoWeb.ImageUploads.allow/3`), it takes
  images (TP-12): an "Add image" picker, and pasting or dropping one into the text (the
  `EditorImages` hook), which inserts its Markdown at the caret. The form's `phx-change`
  handler calls `IdejoWeb.ImageUploads.check/2`.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :mode, :atom, values: [:write, :preview], default: :write
  attr :preview_html, :string, default: ""
  attr :upload, :any, default: nil, doc: "a `Phoenix.LiveView.UploadConfig`, or nil"
  attr :image_error, :string, default: nil

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
      <div
        hidden={@mode == :preview}
        id={"#{@field.id}-write"}
        phx-hook={@upload && "EditorImages"}
        data-upload={@upload && @upload.name}
      >
        <.input field={@field} type="textarea" label={@label} rows="10" />
        <label :if={@upload} class="flex items-center gap-2 text-sm mb-2">
          <span>{gettext("Add image")}</span>
          <.live_file_input upload={@upload} class="file-input file-input-sm" />
        </label>
        <p :if={@image_error} role="alert" class="text-sm text-error mb-2">{@image_error}</p>
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

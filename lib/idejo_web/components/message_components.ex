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

  @spoiler_tags ~r{<span class="spoiler">|</span>}

  @doc """
  The stored HTML of a message in a live topic with its `||spoilers||` (steward decision,
  2026-10-28) ready to reveal, at render time (the stored HTML never changes): each one not
  nested in another is numbered (`data-spoiler`, its place in the message) and, unless
  `revealed` holds that number, is a button named "Spoiler, select to reveal" whose words
  are `inert` until then, so neither the keyboard nor a screen reader reaches what it hides.
  A revealed one is `is-revealed` (nested ones show with it). The `InlineLinks` hook sends
  `"reveal_inline_spoiler"`. Every `<span>` there is a spoiler (`Idejo.Markdown`).
  """
  @spec inline_spoilers(String.t(), [non_neg_integer()]) :: String.t()
  def inline_spoilers(html, revealed) when is_binary(html) do
    if String.contains?(html, ~s(<span class="spoiler">)) do
      @spoiler_tags
      |> Regex.split(html, include_captures: true)
      |> Enum.reduce({[], [], 0}, &spoiler_part(&1, &2, revealed))
      |> elem(0)
      |> Enum.reverse()
      |> IO.iodata_to_binary()
    else
      html
    end
  end

  def inline_spoilers(nil, _revealed), do: ""

  # The parts in order, the closing tags the open spans need (innermost first), and the next
  # spoiler's number.
  defp spoiler_part(~s(<span class="spoiler">), {out, [], n}, revealed) do
    if n in revealed do
      {[~s(<span class="spoiler is-revealed" data-spoiler="#{n}" tabindex="-1">) | out],
       ["</span>"], n + 1}
    else
      label =
        gettext("Spoiler, select to reveal")
        |> Phoenix.HTML.html_escape()
        |> Phoenix.HTML.safe_to_string()

      open =
        ~s(<span class="spoiler" data-spoiler="#{n}" role="button" tabindex="0" ) <>
          ~s(aria-label="#{label}"><span class="spoiler-text" inert>)

      {[open | out], ["</span></span>"], n + 1}
    end
  end

  defp spoiler_part(~s(<span class="spoiler">) = tag, {out, closing, n}, _revealed),
    do: {[tag | out], ["</span>" | closing], n}

  defp spoiler_part("</span>", {out, [close | closing], n}, _revealed),
    do: {[close | out], closing, n}

  defp spoiler_part(part, {out, closing, n}, _revealed), do: {[part | out], closing, n}

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
      <%!-- AX-01: the ARIA tabs pattern; the EditorTabs hook adds the arrow keys. --%>
      <div
        role="tablist"
        id={"#{@field.id}-tabs"}
        aria-label={@label}
        class="tabs tabs-border mb-2"
        phx-hook="EditorTabs"
      >
        <button
          type="button"
          role="tab"
          id={"#{@field.id}-write-tab"}
          class={["tab", @mode == :write && "tab-active"]}
          aria-selected={to_string(@mode == :write)}
          aria-controls={"#{@field.id}-write"}
          tabindex={if @mode == :write, do: "0", else: "-1"}
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
          aria-controls={@mode == :preview && "#{@field.id}-preview"}
          tabindex={if @mode == :preview, do: "0", else: "-1"}
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
        role="tabpanel"
        aria-labelledby={"#{@field.id}-write-tab"}
        phx-hook={@upload && "EditorImages"}
        data-upload={@upload && @upload.name}
      >
        <%!-- TP-10: suggestions while typing @, +, #, / or $ (assets/js/suggest.js). --%>
        <div id={"#{@field.id}-suggest"} class="suggest-anchor" phx-hook="EditorSuggest">
          <.input field={@field} type="textarea" label={@label} rows="10" />
          <ul
            id={"#{@field.id}-suggestions"}
            role="listbox"
            class="suggestions"
            aria-label={IdejoWeb.Suggestions.list_label()}
            phx-update="ignore"
            hidden
          >
          </ul>
        </div>
        <label :if={@upload} class="flex items-center gap-2 text-sm mb-2">
          <span>{gettext("Add image")}</span>
          <.live_file_input upload={@upload} class="file-input file-input-sm" />
        </label>
        <p :if={@image_error} role="alert" class="text-sm text-error mb-2">{@image_error}</p>
      </div>
      <div
        :if={@mode == :preview}
        id={"#{@field.id}-preview"}
        role="tabpanel"
        aria-labelledby={"#{@field.id}-preview-tab"}
      >
        <p :if={String.trim(@preview_html) == ""} class="opacity-70">
          {gettext("Nothing to preview yet.")}
        </p>
        <.body :if={String.trim(@preview_html) != ""} html={@preview_html} />
      </div>
    </div>
    """
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PluginComponents do
  @moduledoc """
  What plugins draw (steward request, 2026-11-08; `Idejo.Plugins`): their blocks under a
  message (`embeds/1`), the dialog that asks for what a block needs (`plugin_dialog/1`) and
  a card opened from its button (`plugin_card/1`). Every block is drawn here from checked
  data; a plugin file only chooses which.
  """
  use IdejoWeb, :html

  alias Idejo.Plugins
  alias Idejo.Plugins.Definition

  # Frames run their own page, never this forum's (`Plugins` refuses this host): no forms,
  # no leaving the page they are in.
  @video_sandbox "allow-scripts allow-same-origin allow-popups allow-presentation"
  @frame_sandbox "allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox"
  @link_rel "noopener noreferrer nofollow ugc"

  attr :embeds, :list, required: true, doc: "the message's embeds that show (`Plugins.shown/2`)"
  attr :message_id, :string, required: true
  attr :live?, :boolean, default: false

  @doc "A message's plugin blocks, in the order they were added."
  def embeds(assigns) do
    ~H"""
    <div :if={@embeds != []} id={"message-#{@message_id}-embeds"} class="plugin-embeds">
      <.embed :for={embed <- @embeds} embed={embed} live?={@live?} />
    </div>
    """
  end

  attr :embed, :map, required: true
  attr :live?, :boolean, required: true

  defp embed(%{embed: %{block: "video"}} = assigns) do
    assigns =
      assign(assigns,
        sandbox: @video_sandbox,
        rel: @link_rel,
        host: host(assigns.embed.data["link"])
      )

    ~H"""
    <figure id={"embed-#{@embed.id}"} class="plugin-embed plugin-video">
      <iframe
        src={@embed.data["src"]}
        title={gettext("Video from %{host}", host: @host)}
        class="plugin-frame is-video"
        sandbox={@sandbox}
        allow="accelerometer; encrypted-media; gyroscope; picture-in-picture; fullscreen"
        allowfullscreen
        loading="lazy"
        referrerpolicy="strict-origin-when-cross-origin"
      ></iframe>
      <figcaption class="plugin-caption">
        <a href={@embed.data["link"]} rel={@rel} target="_blank">
          {gettext("Watch on %{host}", host: @host)}
        </a>
      </figcaption>
    </figure>
    """
  end

  defp embed(%{embed: %{block: "iframe"}} = assigns) do
    assigns =
      assign(assigns,
        sandbox: @frame_sandbox,
        rel: @link_rel,
        host: host(assigns.embed.data["src"])
      )

    ~H"""
    <figure id={"embed-#{@embed.id}"} class="plugin-embed plugin-iframe">
      <iframe
        src={@embed.data["src"]}
        title={gettext("Page from %{host}", host: @host)}
        class="plugin-frame is-page"
        sandbox={@sandbox}
        allow="fullscreen"
        loading="lazy"
        referrerpolicy="strict-origin-when-cross-origin"
      ></iframe>
      <figcaption class="plugin-caption">
        <a href={@embed.data["src"]} rel={@rel} target="_blank">
          {gettext("Open %{host}", host: @host)}
        </a>
      </figcaption>
    </figure>
    """
  end

  defp embed(%{embed: %{block: "button"}} = assigns) do
    assigns = assign(assigns, rel: @link_rel)

    ~H"""
    <a
      id={"embed-#{@embed.id}"}
      href={@embed.data["url"]}
      rel={@rel}
      target="_blank"
      class="btn btn-primary btn-sm plugin-embed plugin-button"
    >
      {@embed.data["label"]}
    </a>
    """
  end

  # Once connected, a button opening the card over the page; without scripts, the card's
  # text folded under its label (AX-04).
  defp embed(%{embed: %{block: "card"}} = assigns) do
    ~H"""
    <button
      :if={@live?}
      id={"embed-#{@embed.id}"}
      type="button"
      class="btn btn-primary btn-sm plugin-embed plugin-card-button"
      phx-click="open_plugin_card"
      phx-value-id={@embed.id}
      aria-haspopup="dialog"
    >
      {@embed.data["label"]}
    </button>
    <details :if={!@live?} id={"embed-#{@embed.id}"} class="plugin-embed plugin-card-details">
      <summary class="btn btn-primary btn-sm">{@embed.data["label"]}</summary>
      <MessageComponents.body html={@embed.data["body_html"] || ""} />
    </details>
    """
  end

  # `forum` (steward request, 2026-11-09): a small card, the logo copied here when posted.
  defp embed(%{embed: %{block: "forum"}} = assigns) do
    assigns = assign(assigns, rel: @link_rel, host: host(assigns.embed.data["url"]))

    ~H"""
    <div id={"embed-#{@embed.id}"} class="plugin-embed plugin-forum">
      <img :if={@embed.data["logo"]} src={@embed.data["logo"]} alt="" class="plugin-forum-logo" />
      <span :if={!@embed.data["logo"]} class="plugin-forum-logo is-initial" aria-hidden="true">
        {String.first(@embed.data["name"] || "?")}
      </span>
      <span class="plugin-forum-text">
        <a href={@embed.data["url"]} rel={@rel} target="_blank" class="plugin-forum-name">
          {@embed.data["name"]}
        </a>
        <span class="plugin-forum-host">{@host}</span>
      </span>
      <a
        href={@embed.data["join"]}
        rel={@rel}
        target="_blank"
        class="btn btn-primary btn-sm"
        aria-label={gettext("Join %{name}", name: @embed.data["name"])}
      >
        {gettext("Join")}
      </a>
    </div>
    """
  end

  defp embed(assigns), do: ~H""

  defp host(nil), do: ""
  defp host(address), do: URI.parse(address).host || ""

  attr :card, :map, required: true, doc: "a card embed"

  @doc "The card a card button opens (`InlineCard` hook; Escape or Close closes it)."
  def plugin_card(assigns) do
    ~H"""
    <dialog
      id="plugin-card"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="close_plugin_card"
      data-return-focus
      aria-labelledby="plugin-card-title"
    >
      <div class="modal-box plugin-card">
        <h2 id="plugin-card-title" class="inline-card-title">{@card.data["label"]}</h2>
        <MessageComponents.body html={@card.data["body_html"] || ""} />
        <div class="modal-action">
          <button
            type="button"
            class="btn btn-sm btn-primary"
            phx-click="close_plugin_card"
            phx-mounted={JS.focus()}
          >
            {gettext("Close")}
          </button>
        </div>
      </div>
    </dialog>
    """
  end

  attr :form, :map,
    required: true,
    doc:
      "%{definition, message_id, params, error}: the plugin, the message it goes under (nil: one of its own)"

  @doc "Asks for what the plugin's block needs (`\"plugin_submit\"`)."
  def plugin_dialog(assigns) do
    assigns =
      assign(assigns,
        definition: assigns.form.definition,
        params: assigns.form.params,
        max_label: Plugins.max_label(),
        max_card: Plugins.max_card()
      )

    ~H"""
    <dialog
      id="plugin-dialog"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="hide_plugin"
      data-return-focus
      aria-labelledby="plugin-dialog-title"
    >
      <div class="modal-box plugin-dialog">
        <h2 id="plugin-dialog-title" class="inline-card-title">{@definition.name}</h2>
        <p :if={@definition.description != ""} class="text-sm mb-2">{@definition.description}</p>
        <.forum_search :if={@definition.block == "forum"} form={@form} />
        <.form
          :if={@definition.block != "forum"}
          for={%{}}
          as={:plugin}
          id="plugin-form"
          phx-submit="plugin_submit"
        >
          <.plugin_fields
            definition={@definition}
            params={@params}
            max_label={@max_label}
            max_card={@max_card}
          />
          <p :if={@form.error} id="plugin-error" role="alert" class="text-sm text-error mt-1">
            {@form.error}
          </p>
          <div class="modal-action">
            <button class="btn btn-sm btn-primary">{gettext("Add")}</button>
            <button type="button" class="btn btn-sm btn-ghost" phx-click="hide_plugin">
              {gettext("Cancel")}
            </button>
          </div>
        </.form>
        <div :if={@definition.block == "forum"}>
          <p :if={@form.error} id="plugin-error" role="alert" class="text-sm text-error mt-1">
            {@form.error}
          </p>
          <div class="modal-action">
            <button type="button" class="btn btn-sm btn-ghost" phx-click="hide_plugin">
              {gettext("Cancel")}
            </button>
          </div>
        </div>
      </div>
    </dialog>
    """
  end

  attr :form, :map, required: true

  # `forum`: the directory's search, then up to five forums to choose from. The logos stay
  # out of the dialog: they are another server's, and only a chosen one is copied here.
  defp forum_search(assigns) do
    ~H"""
    <form
      id="plugin-forum-search"
      phx-change="plugin_forum_search"
      phx-submit="plugin_forum_search"
      role="search"
    >
      <label for="plugin-forum-q" class="label mb-1">{gettext("Search the forums")}</label>
      <input
        id="plugin-forum-q"
        name="q"
        type="search"
        value={@form.query}
        phx-debounce="300"
        autocomplete="off"
        class="input input-sm w-full"
        phx-mounted={JS.focus()}
      />
    </form>
    <p :if={@form.searching?} class="text-sm mt-2" role="status">{gettext("Searching…")}</p>
    <p
      :if={!@form.searching? and @form.results == []}
      id="plugin-forum-none"
      class="text-sm mt-2"
      role="status"
    >
      {gettext("No forum found.")}
    </p>
    <ul :if={@form.results != []} id="plugin-forum-results" class="plugin-forum-results">
      <li :for={{forum, i} <- Enum.with_index(@form.results)}>
        <span class="plugin-forum-text">
          <span class="plugin-forum-name">{forum["name"]}</span>
          <span class="plugin-forum-host">{URI.parse(forum["url"]).host}</span>
        </span>
        <button
          type="button"
          class="btn btn-primary btn-xs"
          phx-click="plugin_forum_pick"
          phx-value-index={i}
          aria-label={gettext("Choose %{name}", name: forum["name"])}
        >
          {gettext("Choose")}
        </button>
      </li>
    </ul>
    """
  end

  attr :definition, Definition, required: true
  attr :params, :map, required: true
  attr :max_label, :integer, required: true
  attr :max_card, :integer, required: true

  defp plugin_fields(%{definition: %{block: "video"}} = assigns) do
    ~H"""
    <label for="plugin-link" class="label mb-1">{gettext("The video's link")}</label>
    <input
      id="plugin-link"
      name="plugin[link]"
      type="url"
      value={@params["link"]}
      required
      class="input input-sm w-full"
      phx-mounted={JS.focus()}
    />
    """
  end

  defp plugin_fields(%{definition: %{block: "iframe"}} = assigns) do
    ~H"""
    <label for="plugin-code" class="label mb-1">
      {gettext("Paste the frame's code (<iframe …>) or its https address")}
    </label>
    <textarea
      id="plugin-code"
      name="plugin[code]"
      rows="4"
      required
      class="textarea textarea-sm w-full font-mono"
      phx-mounted={JS.focus()}
    >{@params["code"]}</textarea>
    """
  end

  defp plugin_fields(%{definition: %{block: "button"}} = assigns) do
    ~H"""
    <label for="plugin-label" class="label mb-1">{gettext("Label")}</label>
    <input
      id="plugin-label"
      name="plugin[label]"
      type="text"
      value={@params["label"]}
      maxlength={@max_label}
      required
      class="input input-sm w-full mb-2"
      phx-mounted={!@params["label"] && JS.focus()}
    />
    <label for="plugin-url" class="label mb-1">{gettext("The link it opens")}</label>
    <input
      id="plugin-url"
      name="plugin[url]"
      type="url"
      value={@params["url"]}
      placeholder="https://"
      required
      class="input input-sm w-full"
      phx-mounted={@params["label"] && JS.focus()}
    />
    """
  end

  defp plugin_fields(%{definition: %{block: "card"}} = assigns) do
    ~H"""
    <label for="plugin-label" class="label mb-1">{gettext("Button label")}</label>
    <input
      id="plugin-label"
      name="plugin[label]"
      type="text"
      value={@params["label"]}
      maxlength={@max_label}
      required
      class="input input-sm w-full mb-2"
      phx-mounted={!@params["label"] && JS.focus()}
    />
    <label for="plugin-body" class="label mb-1">
      {gettext("What the card shows (formatted like a message)")}
    </label>
    <textarea
      id="plugin-body"
      name="plugin[body]"
      rows="6"
      maxlength={@max_card}
      required
      class="textarea textarea-sm w-full"
      phx-mounted={@params["label"] && JS.focus()}
    >{@params["body"]}</textarea>
    """
  end

  @doc "The words for what `Idejo.Plugins.prepare/2` refused."
  @spec error(atom()) :: String.t()
  def error(:link), do: gettext("That link is not one this plugin can show.")
  def error(:code), do: gettext("Give an https address, or the frame's code holding one.")

  def error(:label),
    do: gettext("Write a label, at most %{max} characters.", max: Plugins.max_label())

  def error(:url), do: gettext("Give a link starting with https:// or http://.")

  def error(:body),
    do: gettext("Write what the card shows, at most %{max} characters.", max: Plugins.max_card())

  def error(:forum), do: gettext("Choose one of the forums found.")
  def error(:too_many), do: gettext("This message has as many plugin blocks as it can take.")

  def error(:rate_limited),
    do: gettext("You are sending very fast. Wait a moment, then try again.")

  def error(_), do: gettext("You cannot use this command here.")

  @doc """
  The admin page's words for why a plugin file cannot be used or installed
  (`Idejo.Plugins.problem/0`).
  """
  @spec problem(Idejo.Plugins.problem()) :: String.t()
  def problem({:too_large, kb}), do: gettext("The file is larger than %{kb} KB.", kb: kb)
  def problem(:not_object), do: gettext("The file is not a JSON object.")
  def problem(:not_json), do: gettext("The file is not valid JSON.")
  def problem(:version), do: gettext("\"idejo_plugin\" must be 1.")

  def problem(:command_format),
    do: gettext("\"command\" may only hold lower-case letters, digits and dashes, at most 30.")

  def problem({:missing, field}), do: gettext("\"%{field}\" is missing.", field: field)

  def problem({:too_long, field, max}),
    do: gettext("\"%{field}\" is longer than %{max} characters.", field: field, max: max)

  def problem({:not_text, field}), do: gettext("\"%{field}\" must be text.", field: field)

  def problem({:not_one_of, field, allowed}),
    do:
      gettext("\"%{field}\" must be one of %{values}.",
        field: field,
        values: Enum.join(allowed, ", ")
      )

  def problem({:argument, block, argument}),
    do:
      gettext(~s|A "%{block}" plugin cannot take a "%{argument}" argument.|,
        block: block,
        argument: argument
      )

  def problem(:video),
    do: gettext(~s|A "video" plugin needs "video" with "match" (1 to 10 patterns) and "embed".|)

  def problem(:directory_https), do: gettext(~s|"directory" must be an https address.|)

  def problem(:directory_missing),
    do: gettext(~s|A "forum" plugin needs "directory", its forums directory's address.|)

  def problem(:pattern_invalid),
    do: gettext(~s|A "match" pattern is not a valid regular expression.|)

  def problem(:pattern_too_long),
    do: gettext(~s|Each "match" pattern must be text, at most 300 characters.|)

  def problem(:pattern_no_id), do: gettext(~s|Each "match" pattern needs a group named "id".|)
  def problem(:embed), do: gettext("\"embed\" must be an https address holding {id}.")

  def problem({:reserved, command}),
    do: gettext("!%{command} is already a command of Idejo or an automessage.", command: command)

  def problem({:duplicate, command}),
    do: gettext("Another file already defines !%{command}.", command: command)

  def problem({:installed, command}),
    do:
      gettext("A plugin for !%{command} is installed already. Delete its file first.",
        command: command
      )

  def problem(:unreadable), do: gettext("The file cannot be read.")
  def problem(:not_a_file), do: gettext("Not a file.")
  def problem(:not_writable), do: gettext("The plugins folder cannot be written to.")
end

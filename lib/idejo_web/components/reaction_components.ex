# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ReactionComponents do
  @moduledoc """
  Reactions under a message (TP-17; steward decision, 2026-10-22), in `IdejoWeb.TopicLive`:
  each emoji used, with a count when several people chose it; a click adds or takes back the
  reader's own. A "React" action among the message's others (steward decision, 2026-10-25)
  opens the eight first choices and a + for every emoji (`emoji_picker/1`, a dialog with a search box).
  The LiveView handles `"react"` (`id`, `emoji`), `"emoji_picker"` (`id`), `"emoji_search"`
  and `"close_picker"`.
  """
  use Phoenix.Component
  use Gettext, backend: IdejoWeb.Gettext

  alias Idejo.Emoji
  alias Phoenix.LiveView.JS

  attr :emoji, :map, required: true, doc: "from `Idejo.Emoji`"
  attr :class, :string, default: "emoji"

  @doc "An emoji's image; its alt text is the emoji, or `:name:` for the server's own."
  def emoji_img(assigns) do
    ~H"""
    <img
      src={@emoji.src}
      alt={@emoji.char || ":#{@emoji.name}:"}
      class={@class}
      loading="lazy"
      draggable="false"
    />
    """
  end

  attr :message_id, :string, required: true
  attr :summary, :list, required: true, doc: "from `Idejo.Reactions.summaries/1`"
  attr :viewer, :any, required: true
  attr :can_react?, :boolean, required: true

  @doc "The reactions under a message: buttons for those who may react, plain for others."
  def reaction_bar(assigns) do
    shown = for r <- assigns.summary, emoji <- [Emoji.lookup(r.emoji)], emoji, do: {r, emoji}
    assigns = assign(assigns, :shown, shown)

    ~H"""
    <ul
      :if={@shown != []}
      id={"message-#{@message_id}-reactions"}
      class="reactions"
      aria-label={gettext("Reactions")}
    >
      <li :for={{reaction, emoji} <- @shown}>
        <button
          :if={@can_react?}
          type="button"
          class="reaction"
          aria-pressed={to_string(mine?(reaction, @viewer))}
          aria-label={label(emoji, reaction, @viewer)}
          title={":#{emoji.name}:"}
          phx-click="react"
          phx-value-id={@message_id}
          phx-value-emoji={emoji.name}
        >
          <.emoji_img emoji={emoji} />
          <span :if={reaction.count > 1} class="reaction-count" aria-hidden="true">
            {reaction.count}
          </span>
        </button>
        <span
          :if={!@can_react?}
          class="reaction"
          role="img"
          aria-label={label(emoji, reaction, @viewer)}
          title={":#{emoji.name}:"}
        >
          <.emoji_img emoji={emoji} />
          <span :if={reaction.count > 1} class="reaction-count" aria-hidden="true">
            {reaction.count}
          </span>
        </span>
      </li>
    </ul>
    """
  end

  defp mine?(_reaction, nil), do: false
  defp mine?(reaction, viewer), do: viewer.id in reaction.user_ids

  defp label(emoji, reaction, viewer) do
    who =
      if mine?(reaction, viewer),
        do: ngettext("1 reaction, yours", "%{count} reactions, including yours", reaction.count),
        else: ngettext("1 reaction", "%{count} reactions", reaction.count)

    "#{emoji.char || ":#{emoji.name}:"} #{who}"
  end

  attr :message_id, :string, required: true

  @doc """
  "React" and the first choices: a `<details>`, so it opens from the keyboard too; choosing
  closes it, and so does a click outside it (assets/js/account_menu.js).
  """
  def add_reaction(assigns) do
    assigns = assign(assigns, :defaults, Emoji.defaults())

    ~H"""
    <details id={"message-#{@message_id}-react"} class="add-reaction">
      <summary class="message-action">
        <IdejoWeb.CoreComponents.icon name="hero-face-smile-micro" class="size-4" />{gettext("React")}
      </summary>
      <div class="add-reaction-panel">
        <button
          :for={emoji <- @defaults}
          type="button"
          class="add-reaction-choice"
          aria-label={":#{emoji.name}:"}
          title={":#{emoji.name}:"}
          phx-click={
            JS.push("react", value: %{id: @message_id, emoji: emoji.name})
            |> JS.remove_attribute("open", to: "#message-#{@message_id}-react")
          }
        >
          <.emoji_img emoji={emoji} />
        </button>
        <button
          type="button"
          class="add-reaction-choice"
          aria-label={gettext("More emoji")}
          title={gettext("More emoji")}
          phx-click={
            JS.push("emoji_picker", value: %{id: @message_id})
            |> JS.remove_attribute("open", to: "#message-#{@message_id}-react")
          }
        >
          <span class="add-reaction-more" aria-hidden="true">+</span>
        </button>
      </div>
    </details>
    """
  end

  attr :picker, :map, required: true, doc: "`%{message_id: id}`"

  @doc """
  Every emoji, in groups, with a search box: the + of `add_reaction/1`. Only its frame is
  rendered here; the `EmojiPicker` hook fetches the list (`/emoji-index.json`, kept by the
  browser), draws it and searches it, so opening the picker sends nothing over the live
  connection. A choice is pushed as `"react"`.
  """
  def emoji_picker(assigns) do
    assigns =
      assign(assigns,
        labels: Jason.encode!(Map.new(Emoji.categories(), &{&1, category_name(&1)})),
        index: "/emoji-index.json?v=#{Emoji.index_version()}"
      )

    ~H"""
    <dialog
      id="emoji-picker"
      class="modal"
      phx-hook="InlineCard"
      data-close-event="close_picker"
      aria-labelledby="emoji-picker-title"
    >
      <div class="modal-box emoji-picker">
        <h2 id="emoji-picker-title" class="inline-card-title">{gettext("Add a reaction")}</h2>
        <div
          id="emoji-picker-body"
          class="emoji-picker-body"
          phx-hook="EmojiPicker"
          phx-update="ignore"
          data-src={@index}
          data-message-id={@picker.message_id}
          data-labels={@labels}
        >
          <label for="emoji-search" class="sr-only">{gettext("Search emoji")}</label>
          <input
            type="search"
            id="emoji-search"
            placeholder={gettext("Search emoji")}
            class="input input-sm w-full"
            autocomplete="off"
          />
          <p class="inline-card-meta" data-status>{gettext("Loading emoji…")}</p>
          <p class="inline-card-meta" data-empty hidden>{gettext("No emoji by that name.")}</p>
          <p class="inline-card-meta" data-failed hidden>
            {gettext("The emoji could not be loaded. Close this and try again.")}
          </p>
          <div class="emoji-groups" data-groups></div>
        </div>
        <div class="modal-action">
          <button type="button" class="btn btn-sm btn-ghost" phx-click="close_picker">
            {gettext("Close")}
          </button>
        </div>
      </div>
    </dialog>
    """
  end

  defp category_name("Server"), do: gettext("This server")
  defp category_name("Smileys & Emotion"), do: gettext("Smileys & Emotion")
  defp category_name("People & Body"), do: gettext("People & Body")
  defp category_name("Animals & Nature"), do: gettext("Animals & Nature")
  defp category_name("Food & Drink"), do: gettext("Food & Drink")
  defp category_name("Travel & Places"), do: gettext("Travel & Places")
  defp category_name("Activities"), do: gettext("Activities")
  defp category_name("Objects"), do: gettext("Objects")
  defp category_name("Symbols"), do: gettext("Symbols")
  defp category_name("Flags"), do: gettext("Flags")
  defp category_name(other), do: other
end

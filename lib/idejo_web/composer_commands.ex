# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ComposerCommands do
  @moduledoc """
  The composer's `!` commands (steward decision, 2026-10-23), in one place: the list the
  `Suggest` class shows after `!` (`for_composer/3`) and the Help page (`all/0`). A new
  command is added here, then handled in the `Composer` hook (`assets/js/composer.js`), and
  in the `!tutorial-commands` default (`Idejo.Messages.Automessages.Defaults`).
  """
  use Gettext, backend: IdejoWeb.Gettext

  @type command :: %{name: String.t(), label: String.t(), detail: String.t(), help: String.t()}

  @doc "Every command, in the order the list shows them."
  @spec all() :: [command()]
  def all do
    [
      %{
        name: "image",
        detail: gettext("Add an image at the end of your message"),
        help:
          gettext(
            "Opens your files. The picture you choose goes at the end of your message, not sent yet."
          )
      },
      %{
        name: "gif",
        detail: gettext("Search for a GIF and add it to your message"),
        help:
          gettext(
            "Opens a search for GIFs, the popular ones first. The GIF you choose goes where your cursor is, not sent yet. Only when an administrator has turned GIFs on; they come from an outside service, which sees the address of everyone who searches or reads them."
          )
      },
      %{
        name: "forward",
        detail: gettext("Forward the message you are replying to"),
        help:
          gettext(
            "Opens Forward for the message you are replying to (choose Reply on it first): pick a topic, recent ones first, or search for one. That topic opens with the message in a box over your new message, whole; write what you want to say with it and send. Forward under a message does the same."
          )
      },
      %{
        name: "new-topic",
        detail: gettext("Send, then start a new topic from it"),
        help:
          gettext(
            "Sends what you wrote, then opens New topic with your message as its first message: give it a title. When you were replying, the new topic continues from the message you replied to; that message gets a Continue topic button."
          )
      },
      %{
        name: "poll",
        detail: gettext("Add a poll under your message"),
        help:
          gettext(
            "Sends what you wrote, then asks for a question, its answers, whether several answers may be chosen and how many hours it stays open (decimals work, at most 168). The poll goes under your message, one per message; with nothing written, it is posted on its own. Anyone who may post here votes and may change their vote until it closes; the counts show once you voted, and to everyone once it closed. Nobody sees who voted for what."
          )
      },
      %{
        name: "schedule",
        detail: gettext("Post what you have not sent yet, later"),
        help:
          gettext(
            "Posts the text you have not sent yet in a number of hours (decimals work, at most 168). Only you see it until then, under the box, where Cancel takes it back. It is posted as one finished message, marked scheduled message."
          )
      },
      %{
        name: "spoiler",
        detail: gettext("Hide your message until readers reveal it"),
        help:
          gettext(
            "Sends what you wrote and hides your message behind a blur, with a Reveal spoiler button; quotes and search results show (spoiler) instead of its words. Type !spoiler:overlay text: (ending with a colon, and no colon in the text) to show those words over it instead, also on a message hidden already; quotes then show (spoiler: overlay text). Choose !spoiler again to show it plainly. To hide only part of a message, put || on each side of it."
          )
      }
    ]
    |> Enum.map(&Map.put(&1, :label, "!" <> &1.name))
  end

  @doc """
  The commands an author may use in a composer: `!image` with uploads allowed, `!gif` while
  GIFs are on (`Idejo.Gifs.enabled?/0`, `gifs?`), `!new-topic` when they may start a topic
  somewhere, then the `automessages` they may send there
  (`Idejo.Messages.Automessages.commands_for/2`; steward decisions, 2026-11-01), marked `auto`
  for the `Composer` hook, and last the `plugins` they may use (`Idejo.Plugins.usable/2`;
  steward request, 2026-11-08), marked `plugin` with their `argument`, unless an automessage
  took the name. Only what the list needs.
  """
  @spec for_composer(
          boolean(),
          boolean(),
          [%{name: String.t(), sender: String.t()}],
          boolean(),
          [Idejo.Plugins.Definition.t()]
        ) :: [map()]
  def for_composer(upload?, can_fork?, automessages \\ [], gifs? \\ false, plugins \\ []) do
    own =
      for %{name: name} = command <- all(),
          name != "image" or upload?,
          name != "gif" or gifs?,
          name != "new-topic" or can_fork?,
          do: Map.take(command, [:name, :label, :detail])

    auto =
      for %{name: name, sender: sender} <- automessages do
        %{
          name: name,
          label: "!" <> name,
          detail: gettext("Automessage: the server posts it, as %{sender}", sender: sender),
          auto: true
        }
      end

    taken = MapSet.new(own ++ auto, & &1.name)

    own ++
      auto ++
      for %{command: name} = plugin <- plugins, not MapSet.member?(taken, name) do
        %{
          name: name,
          label: "!" <> name,
          detail: plugin.description,
          plugin: true,
          argument: plugin.argument,
          block: plugin.block
        }
      end
  end
end

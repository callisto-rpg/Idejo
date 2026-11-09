# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Commands do
  @moduledoc """
  The composer's `!` commands (steward decision, 2026-10-23): which exist and which an author
  may use in a topic. Labels and help texts are the web layer's
  (`IdejoWeb.ComposerCommands`); the rules are here, so any client asks the same question.

  Offering a command never grants it: each one's own function refuses on its own
  (`Idejo.Messages.Polls`, `Idejo.Messages.Scheduling`, `Idejo.Messages.set_spoiler/4`,
  `Idejo.Forum.create_topic/4`, `Idejo.Messages.Automessages.post/3`,
  `Idejo.Plugins.attach/4`, …).
  """

  alias Idejo.Accounts.User
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Gifs
  alias Idejo.Messages.Automessages
  alias Idejo.Plugins

  @builtin ~w(image gif forward new-topic poll schedule spoiler)

  @typedoc """
  A command an author may use: one of the composer's own (`:builtin`), an automessage
  (`:automessage`, with its `sender`), or a plugin (`:plugin`, with its `argument` and
  `block`).
  """
  @type t ::
          %{name: String.t(), kind: :builtin}
          | %{name: String.t(), kind: :automessage, sender: String.t()}
          | %{name: String.t(), kind: :plugin, argument: String.t(), block: String.t()}

  @doc "The composer's own command names, in the order the composer lists them."
  @spec builtin() :: [String.t()]
  def builtin, do: @builtin

  @doc """
  Which of the composer's own commands are offered: `!image` with uploads allowed (`upload?`),
  `!gif` while GIFs are on (`gifs?`), `!new-topic` when the author may start a topic from a
  message (`fork?`, `Idejo.Forum.can_fork?/2`); the others always.
  """
  @spec builtin_available(boolean(), boolean(), boolean()) :: [String.t()]
  def builtin_available(upload?, fork?, gifs?) do
    for name <- @builtin,
        name != "image" or upload?,
        name != "gif" or gifs?,
        name != "new-topic" or fork?,
        do: name
  end

  @doc """
  The commands `user` may use in `topic`'s composer: none without the post right
  (`Idejo.Forum.can_post?/2`); else the composer's own (`builtin_available/3`), then the
  automessages they may send there, then the plugins they may use, unless an automessage
  took the name.
  """
  @spec available(User.t() | nil, Topic.t()) :: [t()]
  def available(nil, _topic), do: []

  def available(%User{} = user, %Topic{} = topic) do
    if Forum.can_post?(user, topic) do
      own =
        for name <- builtin_available(true, Forum.can_fork?(user, topic), Gifs.enabled?()),
            do: %{name: name, kind: :builtin}

      auto =
        for %{name: name, sender: sender} <- Automessages.commands_for(user, topic),
            do: %{name: name, kind: :automessage, sender: sender}

      taken = MapSet.new(own ++ auto, & &1.name)

      plugins =
        for plugin <- Plugins.usable(user, topic), not MapSet.member?(taken, plugin.command) do
          %{name: plugin.command, kind: :plugin, argument: plugin.argument, block: plugin.block}
        end

      own ++ auto ++ plugins
    else
      []
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Messages.Automessages.Defaults do
  @moduledoc """
  The automessages every install starts with (steward decision, 2026-11-01), written by the
  migration `AddDefaultAutomessages`: `!tutorial-message`, `!tutorial-commands` and
  `!rules`. Once there they are the administrators' to change or delete; changing this
  text changes only new installs.
  """

  @doc "The default automessages, as `{command, Markdown}`."
  @spec all() :: [{String.t(), String.t()}]
  def all do
    [
      {"tutorial-message", tutorial_message()},
      {"tutorial-commands", tutorial_commands()},
      {"rules", rules()}
    ]
  end

  defp tutorial_message do
    """
    **How writing works here**

    - **Enter** sends what you typed, and everyone sees it at once. Keep typing and press Enter again: your new lines join the same message, which grows while you write.
    - **Ctrl+Enter** (or Enter three times in a row) finishes your message, so the next thing you send starts a new one. The thin line under the box shows when you may start one.
    - **!image** at the start of a word picks a picture to add at the end of your message. You can also paste or drop a picture into the box.

    More on the [Help page](/help).
    """
  end

  defp tutorial_commands do
    """
    **Commands**: type `!` at the start of a word in the box, then pick one.

    - `!image`: add a picture at the end of your message.
    - `!new-topic`: send what you wrote, then start a new topic from it.
    - `!poll`: add a poll under your message, or post one on its own.
    - `!schedule`: post what you have not sent yet, a number of hours later.
    - `!spoiler`: hide your message until readers reveal it; `!spoiler:overlay text:` shows those words over it. To hide only part of a message, put `||` on each side of it.

    Every command is explained on the [Help page](/help).
    """
  end

  defp rules do
    """
    **The rules of this community**

    1. Be kind and respectful. No insults, harassment or hate.
    2. Stay on topic. Something else to talk about? Start a new topic.
    3. No spam, advertising or flooding.
    4. Never share someone else's private information.
    5. Keep it legal and suitable for everyone here. Hide spoilers with `!spoiler`.
    6. Report problems instead of arguing about them, and follow the moderators' decisions.

    Thank you for keeping this place friendly. Everything is on [Rules & Roles](/rules).
    """
  end
end

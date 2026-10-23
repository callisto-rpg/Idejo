# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ModerationHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.ModerationController`.
  """
  use IdejoWeb, :html

  embed_templates "moderation_html/*"

  @doc "An action, in words."
  def action_label("message.close"), do: gettext("Closed an open message")
  def action_label("message.delete"), do: gettext("Deleted a message")
  def action_label("message.edit"), do: gettext("Edited a message")
  def action_label("user.ban"), do: gettext("Banned an account")
  def action_label("user.unban"), do: gettext("Lifted a ban")
  def action_label("topic.lock"), do: gettext("Locked a topic")
  def action_label("topic.unlock"), do: gettext("Unlocked a topic")
  def action_label("topic.pin"), do: gettext("Pinned a topic")
  def action_label("topic.unpin"), do: gettext("Unpinned a topic")
  def action_label("topic.move"), do: gettext("Moved a topic")
  def action_label("topic.tags"), do: gettext("Changed the tags of a topic")
  def action_label("topic.rename"), do: gettext("Renamed a topic")
  def action_label("messages.move"), do: gettext("Moved messages to another thread")
  def action_label("report.resolve"), do: gettext("Resolved reports about a message")
  def action_label("report.dismiss"), do: gettext("Dismissed reports about a message")
  def action_label(action), do: action

  @doc "Where the target of an action is: its permalink or URI path."
  def target_path(%{target_type: "message", target_id: id}), do: ~p"/m/#{id}"
  def target_path(%{target_type: "topic", target_id: id}), do: ~p"/t/#{id}"
  def target_path(%{target_type: "user", target_id: id}), do: ~p"/u/#{id}"

  @doc "What the target is, in words."
  def target_label(%{target_type: "message"}), do: gettext("message")
  def target_label(%{target_type: "topic"}), do: gettext("topic")
  def target_label(%{target_type: "user"}), do: gettext("user")

  @doc "When a ban ends, from its log entry: a time, or for good."
  def ban_until(%{action: "user.ban", details: %{"until" => nil}}), do: gettext("for good")

  def ban_until(%{action: "user.ban", details: %{"until" => until}}),
    do: gettext("until %{time}", time: until)

  def ban_until(_entry), do: nil
end

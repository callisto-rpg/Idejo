# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AppAuthorizeHTML do
  @moduledoc "AP-08: the confirmation and error pages of the official app's sign-in."
  use IdejoWeb, :html

  embed_templates "app_authorize_html/*"

  @doc "Why a sign-in request is refused, in plain words."
  def refusal(:banned), do: gettext("Your account is banned, so the app cannot sign in.")
  def refusal(:inactive), do: gettext("This account cannot sign in.")
  def refusal(:disabled), do: gettext("The idejo app is turned off on this server.")

  def refusal(_invalid),
    do:
      gettext(
        "This sign-in request does not come from the official idejo app, or it is incomplete. Nothing was shared. Close this page and try again from the app."
      )

  @doc "What the app may do, by scope (AP-10)."
  def scope_text("read"), do: gettext("read the categories, topics and messages you can read")

  def scope_text("write"),
    do: gettext("post, edit, react, vote, follow topics and change your profile as you")

  def scope_text("private"), do: gettext("read and write your private conversations")

  def scope_text("moderate"),
    do: gettext("moderate, where you are a moderator, as you would here")

  def scope_text("push"), do: gettext("send notifications to this device")
end

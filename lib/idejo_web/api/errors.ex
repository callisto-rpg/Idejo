# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.Errors do
  @moduledoc """
  The API's one error shape (AP-17; steward decision, 2026-11-10):

      {"error": {"code": "too_soon", "message": "You cannot post a new message yet. …",
                 "details": {…}}}

  `code` is stable: the context's error atom, or one of the API's own (`unauthenticated`,
  `insufficient_scope`, …). `message` is the text the web app shows for it, translated, so
  the app can show it as it is. Every code the API can answer is in `codes/0` with its
  status; an unknown one is a bug, and raises in tests (`test/idejo_web/api/contract_test.exs`).

  Statuses: 400 malformed, 401 unauthenticated, 403 refused on something the user can see,
  404 missing or not visible (never revealing which), 409 a state conflict, 410 an expired
  cursor, 422 validation (with `details.fields`), 429 rate-limited (with `Retry-After`).
  """
  use Gettext, backend: IdejoWeb.Gettext

  import Plug.Conn

  @codes %{
    # The request
    bad_request: 400,
    unauthenticated: 401,
    invalid_token: 401,
    insufficient_scope: 403,
    banned: 403,
    suspended: 403,
    forbidden: 403,
    not_found: 404,
    rate_limited: 429,
    validation: 422,
    cursor_expired: 410,
    internal: 500,
    # Sign-in (RFC 6749 §5.2 names)
    invalid_request: 400,
    invalid_client: 401,
    invalid_grant: 400,
    unsupported_grant_type: 400,
    # Writing
    too_soon: 409,
    locked: 409,
    archived: 409,
    not_open: 409,
    opening: 409,
    blank: 422,
    taken: 409,
    has_poll: 409,
    too_many: 409,
    cooldown: 409,
    closed: 409,
    invalid: 422,
    unknown_emoji: 422,
    link: 422,
    code: 422,
    label: 422,
    url: 422,
    body: 422,
    # Uploads
    too_large: 413,
    not_an_image: 422,
    too_many_pixels: 422,
    not_saved: 422,
    # Accounts and moderation
    passwords_off: 403,
    invalid_password: 422,
    not_bannable: 403,
    not_banned: 409,
    duration: 422,
    past: 422,
    last_owner: 409,
    disabled: 409,
    not_moderated: 409,
    # Further refusals of the contexts
    invalid_target: 422,
    unreadable: 404,
    deleted: 409,
    tag_required: 422,
    invalid_tags: 422,
    reason: 422,
    open: 409,
    not_warnable: 403,
    not_archived: 409,
    inactive: 403,
    archive: 409,
    video: 422,
    question: 422,
    options: 422,
    hours: 422,
    embed: 422,
    forum: 422,
    bad_answer: 422,
    nothing_unread: 409,
    nothing: 422,
    # Push endpoints (PN-16, AP-19)
    not_https: 422,
    not_allowed: 422,
    unresolvable: 422,
    private_address: 422,
    push_disabled: 409
  }

  @doc "Every error code the API answers, with its status."
  @spec codes() :: %{atom() => pos_integer()}
  def codes, do: @codes

  @doc "The status of a code."
  @spec status(atom()) :: pos_integer()
  def status(code), do: Map.fetch!(@codes, code)

  @doc "Whether the API knows the code."
  @spec known?(term()) :: boolean()
  def known?(code), do: is_map_key(@codes, code)

  @doc """
  Sends the error. An unknown code (a context answer the API does not map yet) is sent as
  `forbidden` in production and raises in tests, so it is found.
  """
  @spec send_error(Plug.Conn.t(), atom(), map()) :: Plug.Conn.t()
  def send_error(conn, code, details \\ %{}) do
    code =
      cond do
        known?(code) ->
          code

        Application.get_env(:idejo, :api_strict_errors, false) ->
          raise ArgumentError, "API error code #{inspect(code)} is not documented"

        true ->
          :forbidden
      end

    body = %{
      "error" => %{
        "code" => Atom.to_string(code),
        "message" => message(code),
        "details" => details
      }
    }

    conn
    |> retry_after(code, details)
    |> put_status(status(code))
    |> Phoenix.Controller.json(body)
    |> halt()
  end

  defp retry_after(conn, :rate_limited, %{"retry_after" => seconds}),
    do: put_resp_header(conn, "retry-after", Integer.to_string(seconds))

  defp retry_after(conn, :rate_limited, _details), do: put_resp_header(conn, "retry-after", "60")
  defp retry_after(conn, _code, _details), do: conn

  @doc "The text the web app shows for a code."
  @spec message(atom()) :: String.t()
  def message(:bad_request), do: gettext("The request is not one the server understands.")
  def message(:unauthenticated), do: gettext("You must sign in to access this page.")
  def message(:invalid_token), do: gettext("You were signed out. Please sign in again.")
  def message(:insufficient_scope), do: gettext("The app was not allowed to do this.")
  def message(:banned), do: gettext("Your account is banned.")
  def message(:suspended), do: gettext("Your account is banned for now.")
  def message(:forbidden), do: gettext("You cannot do this here.")
  def message(:not_found), do: gettext("This page does not exist or you cannot view it.")

  def message(:rate_limited),
    do: gettext("You are sending very fast. Wait a moment, then try again.")

  def message(:internal), do: gettext("Something went wrong on the server.")
  def message(:validation), do: gettext("Some fields need a change.")
  def message(:cursor_expired), do: gettext("The topic changed too much. Load it again.")
  def message(:invalid_request), do: gettext("The sign-in request is not complete.")
  def message(:invalid_client), do: gettext("This app is not the official Idejo app.")
  def message(:invalid_grant), do: gettext("Signing in did not work. Please try again.")
  def message(:unsupported_grant_type), do: gettext("The sign-in request is not complete.")

  def message(:too_soon),
    do: gettext("You cannot post a new message yet. Append your old message.")

  def message(:locked), do: gettext("This topic is locked.")
  def message(:archived), do: gettext("This topic is archived.")
  def message(:not_open), do: gettext("This message is not open any more.")
  def message(:opening), do: gettext("The first message of a topic cannot be deleted.")
  def message(:blank), do: gettext("can't be blank")
  def message(:taken), do: gettext("This message has a poll already.")
  def message(:has_poll), do: gettext("This message has a poll already.")
  def message(:too_many), do: gettext("This message cannot take more blocks.")
  def message(:cooldown), do: gettext("This command was posted here lately. Try again later.")
  def message(:closed), do: gettext("This poll is closed.")
  def message(:invalid), do: gettext("This choice is not one of the poll's answers.")
  def message(:unknown_emoji), do: gettext("This emoji is unknown.")
  def message(:link), do: gettext("Paste a link to a video of this site.")
  def message(:code), do: gettext("Paste the code the site gives to embed it, or its address.")
  def message(:label), do: gettext("Give it a label.")
  def message(:url), do: gettext("Give an http or https link.")
  def message(:body), do: gettext("Write the card's text.")
  def message(:too_large), do: gettext("The image is above the server limit.")

  def message(:not_an_image),
    do: gettext("This file is not an image the server takes (JPEG, PNG, GIF or WebP).")

  def message(:too_many_pixels), do: gettext("This image has too many pixels.")
  def message(:not_saved), do: gettext("This image could not be saved.")
  def message(:passwords_off), do: gettext("Passwords are not used on this server.")
  def message(:invalid_password), do: gettext("is not valid")
  def message(:not_bannable), do: gettext("This account cannot be banned.")
  def message(:not_banned), do: gettext("This account is not banned.")
  def message(:duration), do: gettext("Choose how long the ban lasts.")
  def message(:past), do: gettext("Choose how long the ban lasts.")
  def message(:last_owner), do: gettext("The last owner cannot do this.")
  def message(:disabled), do: gettext("This is turned off on this server.")
  def message(:not_moderated), do: gettext("This category has no moderators who could see it.")
  def message(:invalid_target), do: gettext("Choose another place for it.")
  def message(:unreadable), do: gettext("This page does not exist or you cannot view it.")
  def message(:deleted), do: gettext("This message was deleted.")
  def message(:tag_required), do: gettext("Choose at least one tag.")
  def message(:invalid_tags), do: gettext("These tags are not offered here.")
  def message(:reason), do: gettext("Give a reason.")
  def message(:open), do: gettext("This message is still being written.")
  def message(:not_warnable), do: gettext("This member cannot be warned for this message.")
  def message(:not_archived), do: gettext("This topic is not archived.")
  def message(:inactive), do: gettext("This account cannot sign in.")
  def message(:archive), do: gettext("The Archive takes no new topics.")
  def message(:video), do: gettext("Paste a link to a video of this site.")
  def message(:question), do: gettext("Write the poll's question.")
  def message(:options), do: gettext("Give between 2 and 10 answers.")
  def message(:hours), do: gettext("Give a number of hours, at most 168.")
  def message(:embed), do: gettext("This block cannot be added.")
  def message(:forum), do: gettext("Choose a forum.")
  def message(:bad_answer), do: gettext("This answer cannot be used.")
  def message(:nothing), do: gettext("Choose at least one message.")
  def message(:nothing_unread), do: gettext("Nothing to mark unread.")
  def message(:not_https), do: gettext("The push endpoint must use https.")
  def message(:not_allowed), do: gettext("The push endpoint's host is not allowed.")
  def message(:unresolvable), do: gettext("The push endpoint's host cannot be found.")

  def message(:private_address),
    do: gettext("The push endpoint is on a private network.")

  def message(:push_disabled), do: gettext("Push notifications are off on this server.")
end

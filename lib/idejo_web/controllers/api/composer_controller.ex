# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.ComposerController do
  @moduledoc """
  The growing message through the API (AP-14; steward decision, 2026-11-10), following
  `Idejo.Messages.commit/4` and the growing-message invariants exactly:

    * `typing`: the author started typing; the server keeps the time (its own clock), and
      the timers of the next message start there (`Messages.typing/3`, invariant 2);
    * `commit`: the whole open message as the app shows it, after Enter (`break: false`),
      Ctrl+Enter (`break: true`) or a new message after Reply (`new: true`), with
      `reply_to` (the message replied to first) and `forward_of`. Stored before the answer
      (invariant 1). The same automatic punctuation, `held`, `:too_soon` and
      `gm_early_reply` rules as the web composer;
    * `show`: the composer's state, from the one timing formula (`Messages.composer/2`):
      the app draws its countdown from it and never works the rules out itself.

  The same actions serve private conversations (`IdejoWeb.Api.ConversationController`).
  """
  use IdejoWeb.Api.Controller

  alias Idejo.Messages

  def show(conn, %{"id" => id}) do
    with {:ok, topic} <- readable_topic(conn, id), do: json(conn, composer(conn, topic))
  end

  def typing(conn, %{"id" => id} = params) do
    with {:ok, topic} <- readable_topic(conn, id), do: typing_in(conn, topic, params)
  end

  def commit(conn, %{"id" => id} = params) do
    with {:ok, topic} <- readable_topic(conn, id), do: commit_in(conn, topic, params)
  end

  @doc false
  def typing_in(conn, topic, params) do
    with {:ok, _at} <- Messages.typing(user(conn), topic, boolean(params, "typing", true)),
         do: json(conn, composer(conn, topic))
  end

  @doc false
  def commit_in(conn, topic, params) do
    reply_to = params["reply_to"] |> List.wrap() |> Enum.filter(&is_binary/1) |> List.first()

    opts = [
      break: boolean(params, "break"),
      new: boolean(params, "new"),
      reply_to_id: reply_to,
      forwarded_from_id: string(params, "forward_of")
    ]

    with body when is_binary(body) <- string(params, "body_md") || {:error, :bad_request},
         {:ok, message} <- Messages.commit_from_client(user(conn), topic, body, opts) do
      json(conn, %{
        "message" => message && Api.message(user(conn), message),
        "composer" => composer(conn, topic)
      })
    end
  end

  @doc false
  def composer(conn, topic) do
    state = Messages.composer(user(conn), topic)

    %{
      "open_message_id" => state.open_message_id,
      "may_start_new_at" => Api.time(state.may_start_new_at),
      "held_until" => Api.time(state.held_until),
      "typing_since" => Api.time(state.typing_since),
      "window_seconds" => state.window_seconds,
      "unanswered_seconds" => state.unanswered_seconds,
      "reply_allowed_early" => state.reply_allowed_early,
      "may_post" => state.may_post,
      "now" => Api.time(DateTime.utc_now())
    }
  end
end

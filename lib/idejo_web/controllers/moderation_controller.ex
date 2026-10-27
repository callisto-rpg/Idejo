# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ModerationController do
  @moduledoc """
  The Moderation screen (MVP §5), for moderators only (anyone else gets not found):

    * `/moderation`, the report queue (MO-01): open reports in the categories the viewer
      moderates (all of them for owners and administrators), grouped by message; resolving or
      dismissing posts to `/moderation/reports/{message id}` with an optional note.
    * `/moderation/log`, the moderation log (MO-03), newest first, 30 a page.
  """
  use IdejoWeb, :controller

  alias Idejo.Moderation

  def index(conn, _params) do
    user = moderator!(conn)

    render(conn, :index,
      page_title: gettext("Moderation"),
      queue: Moderation.list_open_reports(user)
    )
  end

  # Steward decision, 2026-10-27: a reported private message is deleted from the queue, the
  # only place a moderator sees it; the note is the log's reason.
  def handle_reports(conn, %{"message_id" => id, "outcome" => "delete"} = params) do
    user = moderator!(conn)

    with %{topic: %{private: true}} = message <- Moderation.get_reported_message(user, id),
         {:ok, _message} <- Idejo.Messages.delete_reported_private(user, message, params["note"]) do
      conn
      |> put_flash(:info, gettext("Message deleted. Its reports are resolved."))
      |> redirect(to: ~p"/moderation")
    else
      _ ->
        conn
        |> put_flash(:error, gettext("This message could not be deleted."))
        |> redirect(to: ~p"/moderation")
    end
  end

  def handle_reports(conn, %{"message_id" => id, "outcome" => outcome} = params)
      when outcome in ["resolve", "dismiss"] do
    user = moderator!(conn)

    with %{} = message <- Moderation.get_reported_message(user, id),
         {:ok, _count} <-
           Moderation.handle_reports(
             user,
             message,
             String.to_existing_atom(outcome),
             params["note"]
           ) do
      conn
      |> put_flash(
        :info,
        if(outcome == "resolve",
          do: gettext("Reports resolved."),
          else: gettext("Reports dismissed.")
        )
      )
      |> redirect(to: ~p"/moderation")
    else
      _ ->
        conn
        |> put_flash(:error, gettext("These reports could not be handled."))
        |> redirect(to: ~p"/moderation")
    end
  end

  defp moderator!(conn) do
    user = conn.assigns.current_scope.user

    if Moderation.moderator?(user),
      do: user,
      else: raise(Ecto.NoResultsError, queryable: Idejo.Moderation.Action)
  end

  def log(conn, params) do
    user = conn.assigns.current_scope.user

    if Moderation.moderator?(user) do
      page = page(params)
      {entries, more?} = Moderation.list(user, page: page)

      render(conn, :log,
        page_title: gettext("Moderation log"),
        entries: entries,
        page: page,
        more?: more?
      )
    else
      raise Ecto.NoResultsError, queryable: Idejo.Moderation.Action
    end
  end

  defp page(%{"page" => page}) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page(_params), do: 1
end

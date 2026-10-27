# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ReportController do
  @moduledoc """
  Report a message (MO-01) at `/m/{id}/report`: a plain form asking for a reason, for
  signed-in users and messages they may view and did not write. The report goes to the
  moderators of the message's category; the reporter is told it was sent.
  """
  use IdejoWeb, :controller

  alias Idejo.Forum
  alias Idejo.Moderation

  import Phoenix.Component, only: [to_form: 2]

  def new(conn, %{"id" => id}) do
    message = reportable!(conn, id)

    render(conn, :new,
      message: message,
      form: to_form(Moderation.change_report(), as: :report),
      page_title: gettext("Report a message")
    )
  end

  def create(conn, %{"id" => id, "report" => params}) do
    message = reportable!(conn, id)

    case Moderation.report_message(conn.assigns.current_scope.user, message, params) do
      {:ok, _report} ->
        conn
        |> put_flash(:info, gettext("Thank you. The moderators will look at it."))
        |> redirect(to: ~p"/m/#{message.id}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          message: message,
          form: to_form(Map.put(changeset, :action, :insert), as: :report),
          page_title: gettext("Report a message")
        )

      {:error, _too_many_or_forbidden} ->
        conn
        |> put_flash(:error, gettext("You cannot report this message now."))
        |> redirect(to: ~p"/m/#{message.id}")
    end
  end

  defp reportable!(conn, id) do
    user = conn.assigns.current_scope.user

    # A private conversation's too, for its participants (steward decision, 2026-10-27).
    case Forum.get_readable_message(user, id) do
      %{author_id: author_id, deleted_at: nil} = message when author_id != user.id ->
        Idejo.Repo.preload(message, :author)

      _ ->
        raise Ecto.NoResultsError, queryable: Idejo.Messages.Message
    end
  end
end

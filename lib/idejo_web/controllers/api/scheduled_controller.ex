# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.ScheduledController do
  @moduledoc "Scheduled messages (`!schedule`, AP-12): only their author sees them."
  use IdejoWeb.Api.Controller

  alias Idejo.Messages.Scheduling

  def create(conn, %{"id" => id} = params) do
    with {:ok, topic} <- readable_topic(conn, id),
         {:ok, seconds} <- hours(params["hours"]),
         {:ok, scheduled} <-
           Scheduling.schedule(user(conn), topic, string(params, "body_md") || "", seconds,
             reply_to_id: string(params, "reply_to")
           ) do
      json(conn, scheduled(scheduled))
    end
  end

  defp hours(hours) when is_number(hours), do: hours(to_string(hours))

  defp hours(hours) do
    case Scheduling.parse_hours(hours) do
      {:ok, seconds} -> {:ok, seconds}
      :error -> {:error, :hours}
    end
  end

  def index(conn, %{"id" => id}) do
    with {:ok, topic} <- readable_topic(conn, id),
         do: send_list(conn, Enum.map(Scheduling.list_pending(user(conn), topic), &scheduled/1))
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- Scheduling.cancel(user(conn), id), do: no_content(conn)
  end

  defp scheduled(scheduled) do
    %{
      "id" => scheduled.id,
      "topic_id" => scheduled.topic_id,
      "body_md" => scheduled.body_md,
      "reply_to" => scheduled.reply_to_id,
      "post_at" => Api.time(scheduled.post_at),
      "created_at" => Api.time(scheduled.created_at)
    }
  end
end

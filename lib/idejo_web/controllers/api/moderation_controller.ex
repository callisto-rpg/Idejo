# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.ModerationController do
  @moduledoc """
  Moderation through the API (AP-13; steward decision, 2026-11-10), scope `moderate`: every
  moderation action of the web app, through the same context functions, which check the
  moderator right on the category themselves (MO-01 to MO-04, TP-14, TP-15, GM-16).
  Everything is logged as on the web (MO-03), with the optional `reason`.

  A topic or message the moderator cannot view answers 404; one they can view but not
  moderate, 403.
  """
  use IdejoWeb.Api.Controller

  alias Idejo.{Accounts, Forum, Messages, Moderation}
  alias Idejo.Forum.TopicIcons
  alias Idejo.Moderation.Warnings
  alias IdejoWeb.Api.{CategoryController, UserController}

  ## Reports (MO-01) and the approval queue (MO-04)

  def reports(conn, _params) do
    send_list(
      conn,
      for %{message: message, reports: reports} <- Moderation.list_open_reports(user(conn)) do
        %{
          "message" => reported(message),
          "reports" =>
            Enum.map(reports, fn report ->
              %{
                "id" => report.id,
                "reason" => report.reason,
                "reporter" => Api.person(report.reporter),
                "created_at" => Api.time(report.created_at)
              }
            end)
        }
      end
    )
  end

  # A private conversation's message shows its text, never a way into the conversation.
  defp reported(message) do
    private? = message.topic.private

    %{
      "id" => message.id,
      "author" => Api.person(message.author),
      "body_md" => message.body_md,
      "excerpt" => Forum.excerpt(message),
      "private" => private?,
      "topic_id" => if(private?, do: nil, else: message.topic_id),
      "topic_title" => if(private?, do: nil, else: message.topic.title),
      "url" => if(private?, do: nil, else: Api.base() <> "/m/" <> message.id),
      "opened_at" => Api.time(message.opened_at)
    }
  end

  @doc "`outcome`: `resolve`, `dismiss` or (a private conversation's message) `delete`; `note`."
  def handle_report(conn, %{"id" => id} = params) do
    moderator = user(conn)
    note = string(params, "note")

    with %Idejo.Messages.Message{} = message <-
           Moderation.get_reported_message(moderator, id) || {:error, :not_found},
         {:ok, _} <- handle(moderator, message, params["outcome"], note) do
      no_content(conn)
    end
  end

  defp handle(moderator, message, "resolve", note),
    do: Moderation.handle_reports(moderator, message, :resolve, note)

  defp handle(moderator, message, "dismiss", note),
    do: Moderation.handle_reports(moderator, message, :dismiss, note)

  defp handle(moderator, message, "delete", note),
    do: Messages.delete_reported_private(moderator, message, note)

  defp handle(_moderator, _message, _outcome, _note), do: {:error, :bad_request}

  def pending(conn, _params) do
    send_list(
      conn,
      Enum.map(Forum.list_pending_topics(user(conn)), &CategoryController.pending_topic/1)
    )
  end

  def approve(conn, %{"id" => id}) do
    with {:ok, pending} <- pending_topic(conn, id),
         {:ok, topic} <- Forum.approve_topic(user(conn), pending) do
      json(conn, %{"topic" => Api.topic(user(conn), topic), "pending" => nil})
    end
  end

  def reject(conn, %{"id" => id} = params) do
    with {:ok, pending} <- pending_topic(conn, id),
         {:ok, _} <- Forum.reject_topic(user(conn), pending, string(params, "reason")) do
      no_content(conn)
    end
  end

  defp pending_topic(conn, id) do
    case Forum.get_pending_topic(user(conn), id) do
      nil -> {:error, :not_found}
      pending -> {:ok, pending}
    end
  end

  ## The log (MO-03)

  def log(conn, params) do
    with page when is_integer(page) <- page_number(params, :log) || {:error, :bad_request} do
      {entries, more?} = Moderation.list(user(conn), page: page, per_page: limit(params))
      {next, prev} = page_cursors(:log, page, more?)

      send_page(
        conn,
        for entry <- entries do
          %{
            "id" => entry.id,
            "action" => entry.action,
            "moderator" => entry.moderator && Api.person(entry.moderator),
            "target_type" => entry.target_type,
            "target_id" => entry.target_id,
            "category_id" => entry.category_id,
            "reason" => entry.reason,
            "details" => entry.details,
            "created_at" => Api.time(entry.created_at)
          }
        end,
        next,
        prev
      )
    end
  end

  ## Topics (TP-14, TP-15, MO-02)

  def topic(conn, %{"id" => id}) do
    moderator = user(conn)

    with {:ok, menu} <- Forum.topic_menu(moderator, id),
         {:ok, topic} <- viewable_topic(conn, id) do
      json(conn, %{
        "following" => menu.following,
        "inactive" => menu.inactive,
        "inactive_allowed" => menu.inactive_allowed,
        "archived" => menu.archived,
        "unarchive_to" =>
          menu.unarchive_to && %{"id" => menu.unarchive_to.id, "title" => menu.unarchive_to.name},
        "move_targets" =>
          Enum.map(
            Forum.list_move_targets(moderator, topic),
            &%{"id" => &1.id, "title" => &1.name}
          )
      })
    end
  end

  def lock(conn, params), do: moderate(conn, params, :lock)
  def unlock(conn, params), do: moderate(conn, params, :unlock)
  def pin(conn, params), do: moderate(conn, params, :pin)
  def unpin(conn, params), do: moderate(conn, params, :unpin)

  defp moderate(conn, %{"id" => id} = params, action) do
    on_topic(conn, id, &Forum.moderate_topic(user(conn), &1, action, string(params, "reason")))
  end

  def archive(conn, %{"id" => id} = params),
    do: on_topic(conn, id, &Forum.archive_topic(user(conn), &1, string(params, "reason")))

  @doc "Back to where it was archived from, or `category_id`."
  def unarchive(conn, %{"id" => id} = params) do
    moderator = user(conn)

    on_topic(conn, id, fn topic ->
      target =
        case string(params, "category_id") do
          nil ->
            Forum.unarchive_target(topic)

          category_id ->
            Enum.find(Forum.list_moderated_categories(moderator), &(&1.id == category_id))
        end

      if target,
        do: Forum.unarchive_topic(moderator, topic, target, string(params, "reason")),
        else: {:error, :invalid_target}
    end)
  end

  def move(conn, %{"id" => id} = params) do
    moderator = user(conn)

    on_topic(conn, id, fn topic ->
      case Enum.find(Forum.list_move_targets(moderator, topic), &(&1.id == params["category_id"])) do
        nil -> {:error, :invalid_target}
        target -> Forum.move_topic(moderator, topic, target, string(params, "reason"))
      end
    end)
  end

  def mark_inactive(conn, %{"id" => id}),
    do: on_topic(conn, id, &Forum.mark_inactive(user(conn), &1))

  def icon(conn, %{"id" => id} = params) do
    with {:ok, icon} <- icon(params["icon_id"]),
         do: on_topic(conn, id, &Forum.set_topic_icon(user(conn), &1, icon))
  end

  def make_topical(conn, %{"id" => id} = params) do
    with {:ok, icon} <- icon(params["icon_id"]),
         do: on_topic(conn, id, &Forum.make_topical(user(conn), &1, icon))
  end

  defp icon(nil), do: {:ok, nil}

  defp icon(id) when is_binary(id) do
    case Enum.find(TopicIcons.list(), &(&1.id == id)) do
      nil -> {:error, :invalid_target}
      icon -> {:ok, icon}
    end
  end

  defp icon(_id), do: {:error, :bad_request}

  def autofollow(conn, %{"id" => id}),
    do: on_topic(conn, id, &Forum.set_autofollow(user(conn), &1, true))

  def unautofollow(conn, %{"id" => id}),
    do: on_topic(conn, id, &Forum.set_autofollow(user(conn), &1, false))

  @doc "For good: needs `confirm: true`, as the web's confirmation box."
  def delete_topic(conn, %{"id" => id} = params) do
    with {:ok, topic} <- viewable_topic(conn, id),
         true <-
           params["confirm"] == true ||
             {:error, :validation, %{"fields" => %{"confirm" => ["must be true"]}}},
         {:ok, _deleted} <- Forum.delete_topic(user(conn), topic, string(params, "reason")) do
      no_content(conn)
    end
  end

  defp on_topic(conn, id, action) do
    with {:ok, topic} <- viewable_topic(conn, id),
         {:ok, changed} <- action.(topic) do
      json(
        conn,
        Api.topic(user(conn), Forum.get_viewable_topic(user(conn), changed.id) || changed)
      )
    end
  end

  def topic_icons(conn, _params) do
    icons =
      for icon <- TopicIcons.list(),
          do: %{"id" => icon.id, "name" => icon.name, "url" => Api.absolute(TopicIcons.url(icon))}

    send_list(conn, icons)
  end

  def move_targets(conn, params) do
    topics =
      Forum.search_move_targets(user(conn), string(params, "q") || "", string(params, "topic_id"))

    send_list(conn, Api.topics(user(conn), topics))
  end

  ## Messages (TP-15, MO-02, GM-16)

  @doc "`message_ids`, `topic_id` (an existing topic) or `new` (`{title, category_id}`), `reason`."
  def move_messages(conn, params) do
    moderator = user(conn)
    ids = params["message_ids"] |> List.wrap() |> Enum.filter(&is_binary/1)

    with message_id when is_binary(message_id) <- List.first(ids) || {:error, :bad_request},
         {:ok, message} <- readable_message(conn, message_id),
         {:ok, source} <- viewable_topic(conn, message.topic_id),
         {:ok, target} <- move_target(conn, params),
         {:ok, topic} <-
           Forum.move_messages(moderator, source, ids, target, string(params, "reason")) do
      json(conn, Api.topic(moderator, Forum.get_viewable_topic(moderator, topic.id) || topic))
    end
  end

  defp move_target(_conn, %{"new" => %{"title" => title, "category_id" => category_id}}),
    do: {:ok, {:new, %{"title" => title, "category_id" => category_id}}}

  defp move_target(conn, %{"topic_id" => id}) do
    with {:ok, topic} <- viewable_topic(conn, id), do: {:ok, {:existing, topic}}
  end

  defp move_target(_conn, _params), do: {:error, :bad_request}

  def delete_messages(conn, params) do
    ids = params["message_ids"] |> List.wrap() |> Enum.filter(&is_binary/1)

    with {:ok, topic} <- viewable_topic(conn, params["topic_id"]),
         {:ok, _} <-
           Messages.delete_many_as_moderator(user(conn), topic, ids, string(params, "reason")) do
      no_content(conn)
    end
  end

  def delete_message(conn, %{"id" => id} = params),
    do:
      on_message(
        conn,
        id,
        &Messages.delete_as_moderator(user(conn), &1, string(params, "reason"))
      )

  # The message first (AP-17: one the moderator cannot see is 404 whatever the body).
  def edit_message(conn, %{"id" => id} = params) do
    on_message(conn, id, fn message ->
      case string(params, "body_md") do
        nil -> {:error, :bad_request}
        body -> Messages.edit_as_moderator(user(conn), message, body, string(params, "reason"))
      end
    end)
  end

  def close_message(conn, %{"id" => id} = params),
    do:
      on_message(conn, id, &Messages.close_as_moderator(user(conn), &1, string(params, "reason")))

  defp on_message(conn, id, action) do
    with {:ok, message} <- readable_message(conn, id),
         {:ok, changed} <- action.(message) do
      json(conn, Api.message(user(conn), changed))
    end
  end

  ## Members (MO-02)

  @doc "`message_id` (the message warned about) and `reason`."
  def warn(conn, %{"id" => id} = params) do
    with {:ok, member} <- UserController.visible_user(id),
         {:ok, message} <- readable_message(conn, params["message_id"]),
         true <- message.author_id == member.id || {:error, :not_warnable},
         {:ok, warning} <- Warnings.warn(user(conn), message, string(params, "reason") || "") do
      json(conn, warning(%{warning | moderator: user(conn)}))
    end
  end

  def warnings(conn, %{"id" => id}) do
    with {:ok, member} <- UserController.visible_user(id) do
      send_list(conn, Enum.map(Warnings.visible(user(conn), member), &warning/1))
    end
  end

  defp warning(warning) do
    %{
      "id" => warning.id,
      "reason" => warning.reason,
      "message_id" => warning.message_id,
      "category_id" => warning.category_id,
      "created_at" => Api.time(warning.created_at),
      "moderator" => match?(%Accounts.User{}, warning.moderator) && Api.person(warning.moderator)
    }
  end

  @doc "`days` (1, 7, 30 or 365) or `forever: true`, and `reason`."
  def ban(conn, %{"id" => id} = params) do
    duration = if params["forever"] == true, do: :forever, else: {:days, params["days"]}

    with {:ok, member} <- UserController.visible_user(id),
         {:ok, {banned, socket_ids}} <-
           Accounts.ban_for(user(conn), member, duration, string(params, "reason")) do
      IdejoWeb.UserAuth.disconnect_sessions(socket_ids)
      json(conn, Api.user_card(user(conn), banned))
    end
  end

  def unban(conn, %{"id" => id} = params) do
    with {:ok, member} <- UserController.visible_user(id),
         {:ok, member} <- Accounts.unban_user(user(conn), member, string(params, "reason")) do
      json(conn, Api.user_card(user(conn), member))
    end
  end
end

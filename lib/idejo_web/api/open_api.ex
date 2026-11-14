# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.OpenApi do
  @moduledoc """
  The OpenAPI 3.1 document of API v1 (AP-01; steward decision, 2026-11-10), built as Elixir
  data from `IdejoWeb.Api.Operations` (no library) and served at `/api/v1/openapi.json`.

  Every path, parameter, request body, response schema, error code, the Bearer security
  scheme and each operation's scope (`x-idejo-scope`, and `security`), and the channel
  events under `x-idejo-events` (OpenAPI has no WebSocket model).

  Schemas list their top-level properties exactly: the contract tests
  (`test/idejo_web/api/contract_test.exs`) check every response of the test suite against
  them, so a key added to a response without a line here fails.
  """

  alias IdejoWeb.Api.{Errors, Operations}

  # name => {properties (key => JSON type), required keys}
  @person ~w(id uri username display_name user_tag avatar_url avatar_dark_url role colour deleted system)
  @card @person ++ ~w(bio_md roles joined_at ignored_by_me may_message may_ban banned)
  @me @card ++
        ~w(email verified welcomed intro_due auto_punctuation accepts_private_messages warning_pending administrator moderator server_moderator)
  @topic ~w(id uri title slug url category_id private tags author topical icon created_at last_activity_at messages_count unread_count mention_state followed muted locked archived pinned inactive followed_by_everyone continues_from)
  @message ~w(id uri topic_id url author state deleted_by body_md mentions images spoiler inline_spoilers replies_to forwarded_from poll plugins reactions edited moderator_edited pinned_at versions_count scheduled held anonymous continues_topic_id continued_in cursor opened_at closed_at updated_at)

  @schemas %{
    "Error" => {~w(error), ~w(error)},
    "Person" => {@person, @person},
    "UserCard" => {@card, @card},
    "Me" => {@me, @me},
    "Category" =>
      {~w(id uri title slug url description icon colour group position archive topic_type new_topics topics_count last_activity_at tags permissions),
       ~w(id title slug permissions)},
    "Topic" => {@topic ++ ~w(first_message_id preview), @topic},
    "Tag" => {~w(id name slug), ~w(id name slug)},
    "Message" => {@message, @message},
    "Poll" =>
      {~w(id question multiple hidden_until_closed closes_at closed results_shown total my_votes options),
       ~w(id question options)},
    "Reaction" => {~w(emoji name char image_url count mine), ~w(emoji count mine)},
    "Reactor" => {~w(user emoji), ~w(user emoji)},
    "Version" => {~w(id body_md created_at), ~w(id body_md created_at)},
    "Composer" =>
      {~w(open_message_id may_start_new_at held_until typing_since window_seconds unanswered_seconds reply_allowed_early may_post now),
       ~w(open_message_id may_start_new_at held_until window_seconds unanswered_seconds reply_allowed_early now)},
    "CommitResult" => {~w(message composer), ~w(message composer)},
    "MessageWindow" =>
      {~w(data first_message first_unread next_cursor prev_cursor cursor total), ~w(data cursor)},
    "Changes" => {~w(data cursor more topic), ~w(data cursor more)},
    "Unread" => {~w(following others counter), ~w(following others counter)},
    "Server" =>
      {~w(name url logo_url about_md rules_md privacy_md roles settings emoji default_reactions plugins commands),
       ~w(name url settings)},
    "NotificationSettings" => {~w(email push), ~w(email push)},
    "Token" => {~w(id name scopes signed_in_at last_used_at current), ~w(id name scopes)},
    "TokenGrant" =>
      {~w(access_token token_type scope token_id user), ~w(access_token token_type scope)},
    "Warning" => {~w(id reason message_id category_id created_at moderator), ~w(id reason)},
    "Community" => {~w(name url logo_url), ~w(name url)},
    "PushRegistration" =>
      {~w(id kind name endpoint_host this_device created_at last_success_at), ~w(id kind)},
    "PushTest" => {~w(queued), ~w(queued)},
    "PendingTopic" => {~w(id title category_id body_md created_at), ~w(id title)},
    "TopicCreated" => {~w(topic pending), ~w(topic pending)},
    "SearchHit" =>
      {~w(message_id topic_id topic_title category_id author_name url opened_at excerpt),
       ~w(message_id excerpt)},
    "Suggestion" => {~w(kind insert label id), ~w(kind insert label)},
    "Emoji" => {~w(name char image_url), ~w(name)},
    "Gifs" => {~w(enabled config), ~w(enabled)},
    "RolePage" => {~w(id name slug colour members members_count), ~w(id name members)},
    "Command" => {~w(name kind sender argument block), ~w(name kind)},
    "Scheduled" => {~w(id topic_id body_md reply_to post_at created_at), ~w(id post_at)},
    "ForwardTarget" => {~w(id title url private place), ~w(id title)},
    "ForumEntry" => {~w(name url join logo), ~w(name url)},
    "Upload" => {~w(upload_id url markdown width height), ~w(upload_id url markdown)},
    "Automessage" => {~w(name sender), ~w(name)},
    "Conversation" =>
      {~w(id uri url with unread_count last_message created_at last_activity_at), ~w(id with)},
    "ReportGroup" => {~w(message reports), ~w(message reports)},
    "LogEntry" =>
      {~w(id action moderator target_type target_id category_id reason details created_at),
       ~w(id action)},
    "TopicModeration" =>
      {~w(following inactive inactive_allowed archived unarchive_to move_targets), ~w(following)},
    "TopicIcon" => {~w(id name url), ~w(id url)},
    # Steward request, 2026-11-13: each role's own setting and the category's, by right.
    "TopicPermissions" => {~w(topic_id roles), ~w(topic_id roles)},
    "OpenApi" =>
      {~w(openapi info servers paths components security x-idejo-events x-idejo-error-codes),
       ~w(openapi info paths)},
    "Discovery" =>
      {~w(name url idejo_version logo_url api oauth community account features limits),
       ~w(name url api)},
    # Request bodies
    "TokenRequest" =>
      {~w(grant_type code redirect_uri client_id code_verifier),
       ~w(grant_type code redirect_uri client_id code_verifier)},
    "RevokeRequest" => {~w(token), []},
    "IntroClose" => {~w(hide), []},
    "MeUpdate" =>
      {~w(display_name user_tag bio_md auto_punctuation accepts_private_messages), []},
    "PasswordChange" =>
      {~w(current_password password password_confirmation), ~w(current_password password)},
    "UnifiedPushRequest" => {~w(endpoint p256dh auth device_name), ~w(endpoint p256dh auth)},
    "TopicCreate" => {~w(title body_md tag_ids icon_id topical category_id), ~w(title body_md)},
    "TopicUpdate" => {~w(title tag_ids reason), []},
    "ReadPosition" => {~w(message_id), []},
    "Typing" => {~w(typing), []},
    "Commit" => {~w(body_md break new reply_to forward_of), ~w(body_md)},
    "MessageEdit" => {~w(body_md finish), ~w(body_md)},
    "Spoiler" => {~w(overlay), []},
    "ScheduleCreate" => {~w(body_md hours reply_to), ~w(body_md hours)},
    "PollCreate" =>
      {~w(message_id question options multiple hours hidden reply_to), ~w(question options hours)},
    "Vote" => {~w(option_ids), ~w(option_ids)},
    "PluginRun" => {~w(params message_id reply_to), []},
    "Report" => {~w(reason), ~w(reason)},
    "ConversationCreate" => {~w(user_id), ~w(user_id)},
    "ReportOutcome" => {~w(outcome note), ~w(outcome)},
    "Reason" => {~w(reason), []},
    "Unarchive" => {~w(category_id reason), []},
    "Move" => {~w(category_id reason), ~w(category_id)},
    "Icon" => {~w(icon_id), []},
    "TopicPermissionsUpdate" => {~w(settings), ~w(settings)},
    "DeleteTopic" => {~w(confirm reason), ~w(confirm)},
    "MoveMessages" => {~w(message_ids topic_id new reason), ~w(message_ids)},
    "DeleteMessages" => {~w(topic_id message_ids reason), ~w(topic_id message_ids)},
    "ModeratorEdit" => {~w(body_md reason), ~w(body_md)},
    "Warn" => {~w(message_id reason), ~w(message_id reason)},
    "Ban" => {~w(days forever reason), []}
  }

  @types %{
    "id" => "string",
    "uri" => "string",
    "url" => "string",
    "title" => "string",
    "name" => "string",
    "slug" => "string",
    "body_md" => "string",
    "reason" => "string",
    "cursor" => "integer",
    "total" => "integer",
    "count" => "integer",
    "position" => "integer",
    "messages_count" => "integer",
    "unread_count" => "integer",
    "topics_count" => "integer",
    "window_seconds" => "integer",
    "unanswered_seconds" => "integer",
    "versions_count" => "integer",
    "width" => "integer",
    "height" => "integer",
    "queued" => "integer",
    "following" => "array",
    "days" => "integer",
    "hours" => "number",
    "data" => "array",
    "tags" => "array",
    "tag_ids" => "array",
    "roles" => "array",
    "mentions" => "array",
    "images" => "array",
    "replies_to" => "array",
    "plugins" => "array",
    "commands" => "array",
    "reactions" => "array",
    "continued_in" => "array",
    "options" => "array",
    "option_ids" => "array",
    "my_votes" => "array",
    "message_ids" => "array",
    "scopes" => "array",
    "features" => "array",
    "members" => "array",
    "reports" => "array",
    "with" => "array",
    "emoji" => "array",
    "default_reactions" => "array",
    "excerpt" => "array",
    "move_targets" => "array",
    "reply_to" => "array"
  }

  @booleans ~w(deleted system ignored_by_me may_message may_ban banned verified welcomed intro_due hide auto_punctuation accepts_private_messages warning_pending administrator moderator server_moderator archive private topical followed muted locked archived pinned inactive followed_by_everyone inline_spoilers edited moderator_edited scheduled held anonymous multiple hidden_until_closed closed results_shown mine reply_allowed_early may_post more current this_device enabled break new finish typing hidden confirm forever)

  @doc "The whole document."
  @spec document() :: map()
  def document do
    %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "idejo API",
        "version" => "1",
        "description" =>
          "The API of an idejo forum, for the official app (org.idejo.app). Within v1 only additive changes are made. See docs/api-guide.md.",
        "license" => %{"name" => "AGPL-3.0-only", "identifier" => "AGPL-3.0-only"}
      },
      "servers" => [%{"url" => Idejo.Api.base() <> "/api/v1"}],
      "security" => [%{"bearer" => []}],
      "paths" => paths(),
      "components" => %{
        "schemas" => schemas(),
        "securitySchemes" => %{
          "bearer" => %{
            "type" => "http",
            "scheme" => "bearer",
            "description" =>
              "A device token, `idj_…`, from /oauth/token. Scopes: read, write, private, moderate, push."
          }
        }
      },
      "x-idejo-error-codes" =>
        Map.new(Errors.codes(), fn {code, status} ->
          {Atom.to_string(code), %{"status" => status, "message" => Errors.message(code)}}
        end),
      "x-idejo-events" => events()
    }
  end

  @doc "The schemas' properties and required keys, for the contract tests."
  @spec schema(String.t()) :: {[String.t()], [String.t()]}
  def schema(name), do: Map.fetch!(@schemas, name)

  defp schemas do
    Map.new(@schemas, fn {name, {properties, required}} ->
      {name,
       %{
         "type" => "object",
         "properties" => Map.new(properties, &{&1, property(&1)}),
         "required" => required
       }}
    end)
  end

  defp property(key) do
    cond do
      key in @booleans ->
        %{"type" => ["boolean", "null"]}

      Map.has_key?(@types, key) ->
        %{"type" => [@types[key], "null"]}

      String.ends_with?(key, "_at") or key in ~w(now) ->
        %{"type" => ["string", "null"], "format" => "date-time"}

      String.ends_with?(key, "_id") ->
        %{"type" => ["string", "null"]}

      true ->
        %{}
    end
  end

  defp paths do
    Operations.all()
    |> Enum.group_by(& &1.path)
    |> Map.new(fn {path, ops} ->
      {path, Map.new(ops, &{Atom.to_string(&1.method), operation(&1)})}
    end)
  end

  defp operation(op) do
    %{
      "operationId" =>
        "#{Macro.camelize(Atom.to_string(op.action))}#{op.controller |> Module.split() |> List.last()}",
      "summary" => op.summary,
      "tags" => [op.tag],
      "x-idejo-scope" => op.scope,
      "x-idejo-requirement" => op.req,
      "security" => if(op.scope, do: [%{"bearer" => [op.scope]}], else: []),
      "parameters" => path_parameters(op.path) ++ query_parameters(op.query),
      "responses" => responses(op)
    }
    |> put_body(op)
  end

  defp path_parameters(path) do
    for [_, name] <- Regex.scan(~r/\{(\w+)\}/, path) do
      %{"name" => name, "in" => "path", "required" => true, "schema" => %{"type" => "string"}}
    end
  end

  defp query_parameters(query) do
    for {name, type, description} <- query do
      %{
        "name" => name,
        "in" => "query",
        "required" => false,
        "description" => description,
        "schema" => %{"type" => type}
      }
    end
  end

  defp put_body(map, %{multipart: true}) do
    Map.put(map, "requestBody", %{
      "required" => true,
      "content" => %{
        "multipart/form-data" => %{
          "schema" => %{
            "type" => "object",
            "properties" => %{"image" => %{"type" => "string", "format" => "binary"}},
            "required" => ["image"]
          }
        }
      }
    })
  end

  defp put_body(map, %{body: nil}), do: map

  defp put_body(map, %{body: body}) do
    Map.put(map, "requestBody", %{
      "content" => %{
        "application/json" => %{"schema" => ref(body)},
        "application/x-www-form-urlencoded" => %{"schema" => ref(body)}
      }
    })
  end

  defp responses(op) do
    errors =
      for status <- [400, 401, 403, 404, 409, 410, 413, 422, 429], into: %{} do
        {Integer.to_string(status),
         %{
           "description" => error_description(status),
           "content" => %{"application/json" => %{"schema" => ref("Error")}}
         }}
      end

    Map.merge(errors, success(op.response))
  end

  defp error_description(status) do
    codes = for {code, ^status} <- Errors.codes(), do: "`#{code}`"
    "Error: " <> Enum.join(Enum.sort(codes), ", ")
  end

  defp success(:no_content), do: %{"204" => %{"description" => "Done."}}

  defp success({:page, name}),
    do:
      ok(%{
        "type" => "object",
        "properties" => %{
          "data" => %{"type" => "array", "items" => ref(name)},
          "next_cursor" => %{"type" => ["string", "null"]},
          "prev_cursor" => %{"type" => ["string", "null"]}
        },
        "required" => ~w(data next_cursor prev_cursor)
      })

  defp success({:list, name}),
    do:
      ok(%{
        "type" => "object",
        "properties" => %{"data" => %{"type" => "array", "items" => ref(name)}},
        "required" => ["data"]
      })

  defp success(name), do: ok(ref(name))

  defp ok(schema),
    do: %{
      "200" => %{
        "description" => "OK",
        "content" => %{"application/json" => %{"schema" => schema}}
      }
    }

  defp ref(name), do: %{"$ref" => "#/components/schemas/" <> name}

  @doc "The channel events (AP-15), described as data (OpenAPI has no WebSocket model)."
  @spec events() :: map()
  def events do
    message = "Message (payload `message`, with `cursor`)"

    %{
      "socket" =>
        "/api/v1/socket (Phoenix Channels, protocol 2.0.0); connect params: {\"token\": \"idj_…\"}",
      "channels" => %{
        "user:me" => %{
          "join" => "Always allowed for the token's user. Reply: {\"unread\": {count, level}}",
          "events" => %{
            "unread.changed" => "{count, level}: the Unread counter",
            "notification" =>
              "{kind, message_id, topic_id, topic_title, author_name, excerpt}: the web's bubbles (mention, reply, role_mention, follow, reaction, warning)",
            "conversation.updated" =>
              "{conversation_id}: a private conversation has something new",
            "scheduled.posted" =>
              "{message_id, topic_id}: one of the user's scheduled messages was posted",
            "token.revoked" => "{token_id}: this device is signed out; the socket closes",
            "settings.changed" =>
              "{keys}: settings that change how a client behaves (GET /server again)"
          }
        },
        "topic:<id>" => %{
          "join" =>
            "Needs the view right (404-like refusal `{\"reason\": \"not_found\"}`). Reply: {\"cursor\": n}. The member is removed with `forbidden` when they lose the right.",
          "events" => %{
            "message.opened" => message,
            "message.appended" => message,
            "message.edited" => message,
            "message.closed" => message,
            "message.deleted" => message,
            "reaction.changed" => "{message_id, reactions}",
            "poll.updated" => "{message_id, poll}",
            "topic.updated" => "Topic (title, tags, lock, pin, icon)",
            "topic.moved" => "Topic",
            "topic.archived" => "Topic",
            "messages.moved" => "{topic_id}: messages moved in or out; reload the window",
            "forbidden" => "{reason}: the right was lost; the channel is left"
          },
          "pushes" => %{
            "typing" =>
              "{typing: true|false}: as POST /topics/{id}/composer/typing. Never broadcast."
          }
        },
        "conversation:<id>" => %{
          "join" => "Participants only, scope private.",
          "events" => "As topic:<id>"
        },
        "category:<id>" => %{
          "join" => "Needs the view right.",
          "events" => %{
            "topic.created" => "Topic",
            "topic.activity" => "{topic_id, last_activity_at, messages_count}",
            "topic.moved" => "{topic_id, from, to}",
            "topic.archived" => "{topic_id}"
          }
        }
      }
    }
  end
end

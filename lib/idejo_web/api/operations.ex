# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.Operations do
  @moduledoc """
  Every operation of API v1 (AP-01, AP-10 to AP-14; steward decision, 2026-11-10), as data:
  method, path (OpenAPI style, `{id}`), controller and action, the scope a token needs,
  the response schema, the query parameters and request body, and the requirement it
  serves.

  One list for everything: `IdejoWeb.Router` makes the routes from it, `IdejoWeb.Plugs.ApiAuth`
  checks each route's scope from it, `IdejoWeb.Api.OpenApi` documents it, and the tests
  walk it (every route refuses no token, a revoked token and a token without its scope;
  every id-taking route answers 404 for what the user cannot see). A new endpoint is a new
  line here.

  Scopes (AP-10): `read` every GET, `write` posting, editing, reacting, voting, following
  and the profile, `private` private conversations, `moderate` moderation (the moderator
  right on the category is still checked by the context), `push` UnifiedPush. `nil`: no
  token needed. A route in a private conversation also needs `private` (checked once the
  conversation is found).

  Responses: a schema name, `{:page, name}` (a cursor page of them), `{:list, name}`
  (`{"data": [...]}`), or `:no_content` (204).
  """

  alias IdejoWeb.Api

  @type op :: %{
          method: :get | :post | :put | :patch | :delete,
          path: String.t(),
          controller: module(),
          action: atom(),
          scope: String.t() | nil,
          response: term(),
          summary: String.t(),
          query: [{String.t(), String.t(), String.t()}],
          body: String.t() | nil,
          multipart: boolean(),
          req: String.t(),
          tag: String.t()
        }

  @page [
    {"cursor", "string", "An opaque cursor from `next_cursor`."},
    {"limit", "integer", "1 to 100, 50 by default."}
  ]

  defp op(method, path, controller, action, scope, response, summary, opts \\ []) do
    %{
      method: method,
      path: path,
      controller: Module.concat(Api, controller),
      action: action,
      scope: scope,
      response: response,
      summary: summary,
      query: Keyword.get(opts, :query, []),
      body: Keyword.get(opts, :body),
      multipart: Keyword.get(opts, :multipart, false),
      req: Keyword.get(opts, :req, "AP-12"),
      tag: Keyword.get(opts, :tag, tag_of(path))
    }
  end

  defp tag_of(path), do: path |> String.split("/", trim: true) |> hd()

  @doc "Every operation, in the order of the API guide."
  @spec all() :: [op()]
  def all do
    # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
    [
      # Documents and sign-in (AP-01, AP-08, AP-09)
      op(:get, "/openapi.json", OpenApiController, :show, nil, "OpenApi", "This document.",
        req: "AP-01",
        tag: "meta"
      ),
      op(
        :post,
        "/oauth/token",
        OAuthController,
        :token,
        nil,
        "TokenGrant",
        "Exchanges an authorization code for a device token (PKCE).",
        body: "TokenRequest",
        req: "AP-08",
        tag: "oauth"
      ),
      op(
        :post,
        "/oauth/revoke",
        OAuthController,
        :revoke,
        nil,
        :no_content,
        "Revokes the token given as Bearer or `token` (RFC 7009). Always 204.",
        body: "RevokeRequest",
        req: "AP-09",
        tag: "oauth"
      ),

      # The server and the user
      op(
        :get,
        "/server",
        ServerController,
        :show,
        "read",
        "Server",
        "The server, its rules, roles, settings for clients, emoji and commands."
      ),
      op(:get, "/me", MeController, :show, "read", "Me", "The signed-in user, with their email."),
      op(
        :patch,
        "/me",
        MeController,
        :update,
        "write",
        "Me",
        "Changes the display name, user tag, bio, automatic punctuation or private messages choice.",
        body: "MeUpdate"
      ),
      op(
        :put,
        "/me/password",
        MeController,
        :password,
        "write",
        :no_content,
        "Changes the password. Every other session and device signs in again.",
        body: "PasswordChange"
      ),
      op(
        :put,
        "/me/avatar",
        MeController,
        :avatar,
        "write",
        "Me",
        "Sets the picture (multipart `image`).",
        multipart: true
      ),
      op(
        :delete,
        "/me/avatar",
        MeController,
        :delete_avatar,
        "write",
        "Me",
        "Removes the picture."
      ),
      op(
        :put,
        "/me/avatar-dark",
        MeController,
        :avatar_dark,
        "write",
        "Me",
        "Sets the dark theme's picture (multipart `image`).",
        multipart: true
      ),
      op(
        :delete,
        "/me/avatar-dark",
        MeController,
        :delete_avatar_dark,
        "write",
        "Me",
        "Removes the dark theme's picture."
      ),
      op(
        :get,
        "/me/notification-settings",
        MeController,
        :notification_settings,
        "read",
        "NotificationSettings",
        "Email summary choices and push types (PN-11)."
      ),
      op(
        :patch,
        "/me/notification-settings",
        MeController,
        :update_notification_settings,
        "write",
        "NotificationSettings",
        "Changes email summary choices and push types.",
        body: "NotificationSettings"
      ),
      op(
        :get,
        "/me/tokens",
        MeController,
        :tokens,
        "read",
        {:list, "Token"},
        "The user's signed-in devices (AP-09).",
        req: "AP-09"
      ),
      op(
        :delete,
        "/me/tokens/{id}",
        MeController,
        :delete_token,
        "write",
        :no_content,
        "Signs a device out.",
        req: "AP-09"
      ),
      op(
        :put,
        "/me/roles/{id}",
        MeController,
        :add_role,
        "write",
        "Me",
        "Takes a role members may choose."
      ),
      op(
        :delete,
        "/me/roles/{id}",
        MeController,
        :remove_role,
        "write",
        "Me",
        "Leaves a role members may choose."
      ),
      op(
        :post,
        "/me/welcome",
        MeController,
        :welcome,
        "write",
        "Me",
        "Marks the welcome card (About, Rules, roles) seen."
      ),
      op(
        :get,
        "/me/warnings",
        MeController,
        :warnings,
        "read",
        {:list, "Warning"},
        "Warnings not acknowledged yet (MO-02)."
      ),
      op(
        :post,
        "/me/warnings/acknowledge",
        MeController,
        :acknowledge_warnings,
        "write",
        :no_content,
        "\"I understand\": the warnings are seen."
      ),
      op(
        :get,
        "/me/ignored",
        MeController,
        :ignored,
        "read",
        {:list, "Person"},
        "The users the user ignores (AC-06)."
      ),
      op(
        :get,
        "/me/communities",
        MeController,
        :communities,
        "read",
        {:list, "Community"},
        "The other forums the user joined, as the community menu shows them.",
        req: "AP-12"
      ),
      op(
        :get,
        "/me/push",
        PushController,
        :index,
        "push",
        {:list, "PushRegistration"},
        "Browsers and app endpoints taking push.",
        req: "AP-19"
      ),
      op(
        :post,
        "/me/push/unifiedpush",
        PushController,
        :register,
        "push",
        "PushRegistration",
        "Registers a UnifiedPush endpoint with Web Push keys.",
        body: "UnifiedPushRequest",
        req: "AP-19"
      ),
      op(
        :delete,
        "/me/push/unifiedpush/{id}",
        PushController,
        :delete,
        "push",
        :no_content,
        "Removes a push registration.",
        req: "AP-19"
      ),
      op(
        :post,
        "/me/push/test",
        PushController,
        :test,
        "push",
        "PushTest",
        "Sends a test notification to every device.",
        req: "AP-19"
      ),

      # Browsing
      op(
        :get,
        "/categories",
        CategoryController,
        :index,
        "read",
        {:list, "Category"},
        "Categories the user may view, with groups and rights."
      ),
      op(:get, "/categories/{id}", CategoryController, :show, "read", "Category", "A category."),
      op(
        :get,
        "/categories/{id}/topics",
        CategoryController,
        :topics,
        "read",
        {:page, "Topic"},
        "A category's topics, pinned first.",
        query: @page ++ [{"expanded", "boolean", "Adds each topic's preview."}]
      ),
      op(
        :get,
        "/categories/{id}/pending",
        CategoryController,
        :pending,
        "read",
        {:list, "PendingTopic"},
        "The user's own topics waiting for approval there (MO-04)."
      ),
      op(
        :post,
        "/categories/{id}/topics",
        CategoryController,
        :create_topic,
        "write",
        "TopicCreated",
        "Starts a topic; it may wait for approval.",
        body: "TopicCreate"
      ),
      op(
        :get,
        "/topics/active",
        TopicController,
        :active,
        "read",
        {:list, "Topic"},
        "The most recently active topics.",
        query: [{"expanded", "boolean", "Adds each topic's preview."}]
      ),
      op(
        :get,
        "/topics",
        TopicController,
        :tagged,
        "read",
        {:page, "Topic"},
        "Topics carrying the tags (Filter by tag).",
        query:
          @page ++
            [
              {"tags", "string", "Tag slugs, comma separated."},
              {"operator", "string", "`and` (default) or `or`."}
            ]
      ),
      op(
        :get,
        "/tags",
        TopicController,
        :tags,
        "read",
        {:list, "Tag"},
        "Tags the user may filter by."
      ),
      op(
        :get,
        "/unread",
        TopicController,
        :unread,
        "read",
        "Unread",
        "The Unread page: followed topics, then others, and the counter.",
        query: @page
      ),
      op(
        :get,
        "/search",
        ServerController,
        :search,
        "read",
        {:page, "SearchHit"},
        "Full-text search, permission-aware.",
        query:
          @page ++
            [{"q", "string", "Words to find."}, {"category_id", "string", "Only this category."}]
      ),
      op(
        :get,
        "/suggest",
        ServerController,
        :suggest,
        "read",
        {:list, "Suggestion"},
        "The composer's suggestions after @ + # / $ &.",
        query: [
          {"sigil", "string", "One of @ + # / $ &."},
          {"q", "string", "What follows the sign."},
          {"topic_id", "string", "The topic written in."}
        ]
      ),
      op(:get, "/emoji", ServerController, :emoji, "read", {:list, "Emoji"}, "Emoji by name.",
        query: [{"q", "string", "Part of a name."}]
      ),
      op(
        :get,
        "/gifs",
        ServerController,
        :gifs,
        "read",
        "Gifs",
        "The GIF provider's settings, for the app to search it directly (as browsers do)."
      ),
      op(:get, "/users/{id}", UserController, :show, "read", "UserCard", "A user card."),
      op(
        :get,
        "/roles/{id}",
        UserController,
        :role,
        "read",
        "RolePage",
        "A role by its slug, with members (+role links)."
      ),

      # Topics
      op(
        :get,
        "/topics/{id}",
        TopicController,
        :show,
        "read",
        "Topic",
        "A topic, or a private conversation of the user's (scope `private`)."
      ),
      op(
        :patch,
        "/topics/{id}",
        TopicController,
        :update,
        "write",
        "Topic",
        "Changes the title (the starter, or a moderator) or the tags (the tag right).",
        body: "TopicUpdate"
      ),
      op(
        :put,
        "/topics/{id}/follow",
        TopicController,
        :follow,
        "write",
        "Topic",
        "Follows a topic."
      ),
      op(
        :delete,
        "/topics/{id}/follow",
        TopicController,
        :unfollow,
        "write",
        "Topic",
        "Unfollows a topic."
      ),
      op(
        :put,
        "/topics/{id}/mute",
        TopicController,
        :mute,
        "write",
        "Topic",
        "Unfollows and mutes a topic."
      ),
      op(
        :delete,
        "/topics/{id}/mute",
        TopicController,
        :unmute,
        "write",
        "Topic",
        "Lifts the mute: follows it again."
      ),
      op(
        :post,
        "/topics/{id}/mark-unread",
        TopicController,
        :mark_unread,
        "write",
        "Topic",
        "Makes its latest message by someone else new again."
      ),
      op(
        :put,
        "/topics/{id}/read",
        TopicController,
        :read,
        "write",
        "Topic",
        "Marks the topic read up to its latest message (TP-07).",
        body: "ReadPosition"
      ),
      op(
        :get,
        "/topics/{id}/messages",
        TopicController,
        :messages,
        "read",
        "MessageWindow",
        "A window of messages, the first message always included.",
        query:
          @page ++
            [
              {"around", "string", "A message id: the window around it."},
              {"first_unread", "boolean", "Land on the first unread message."}
            ],
        req: "AP-14"
      ),
      op(
        :get,
        "/topics/{id}/changes",
        TopicController,
        :changes,
        "read",
        "Changes",
        "Every message change since a cursor (AP-16).",
        query: [
          {"since", "integer", "The last cursor the app saw."},
          {"limit", "integer", "1 to 100."}
        ],
        req: "AP-16"
      ),
      op(
        :get,
        "/topics/{id}/commands",
        TopicController,
        :commands,
        "read",
        {:list, "Command"},
        "The ! commands the user may use in the topic."
      ),

      # The growing message (AP-14)
      op(
        :get,
        "/topics/{id}/composer",
        ComposerController,
        :show,
        "read",
        "Composer",
        "The composer's state from the server's timing rules.",
        req: "AP-14"
      ),
      op(
        :post,
        "/topics/{id}/composer/typing",
        ComposerController,
        :typing,
        "write",
        "Composer",
        "The author started typing (or emptied the box).",
        body: "Typing",
        req: "AP-14"
      ),
      op(
        :post,
        "/topics/{id}/composer/commit",
        ComposerController,
        :commit,
        "write",
        "CommitResult",
        "Enter (`break: false`), Ctrl+Enter (`break: true`) or a new message after Reply (`new: true`).",
        body: "Commit",
        req: "AP-14"
      ),
      op(:get, "/messages/{id}", MessageController, :show, "read", "Message", "A message.",
        req: "AP-14"
      ),
      op(
        :put,
        "/messages/{id}",
        MessageController,
        :update,
        "write",
        "Message",
        "Edits the author's closed message; `finish` ends the edit (Ctrl+Enter).",
        body: "MessageEdit",
        req: "AP-14"
      ),
      op(
        :delete,
        "/messages/{id}",
        MessageController,
        :delete,
        "write",
        "Message",
        "The author deletes their message (not a topic's first).",
        req: "AP-14"
      ),
      op(
        :get,
        "/messages/{id}/versions",
        MessageController,
        :versions,
        "read",
        {:list, "Version"},
        "Earlier versions, for moderators of the category (MO-06)."
      ),
      op(
        :put,
        "/messages/{id}/spoiler",
        MessageController,
        :spoiler,
        "write",
        "Message",
        "Marks the author's message a spoiler, with an optional overlay.",
        body: "Spoiler"
      ),
      op(
        :delete,
        "/messages/{id}/spoiler",
        MessageController,
        :unspoiler,
        "write",
        "Message",
        "No longer a spoiler."
      ),
      op(
        :post,
        "/messages/{id}/new-topic",
        MessageController,
        :new_topic,
        "write",
        "TopicCreated",
        "A new topic continuing from this message (TP-09).",
        body: "TopicCreate"
      ),
      op(
        :put,
        "/messages/{id}/pin",
        ModerationController,
        :pin_message,
        "moderate",
        "Message",
        "Pins the message to its topic's navigator (`pinned_at`).",
        req: "AP-13"
      ),
      op(
        :delete,
        "/messages/{id}/pin",
        ModerationController,
        :unpin_message,
        "moderate",
        "Message",
        "Unpins the message.",
        req: "AP-13"
      ),
      op(
        :get,
        "/topics/{id}/pins",
        TopicController,
        :pins,
        "read",
        {:list, "Message"},
        "The topic's pinned messages, oldest pin first."
      ),
      op(
        :post,
        "/topics/{id}/scheduled",
        ScheduledController,
        :create,
        "write",
        "Scheduled",
        "Schedules a message (at most 168 hours).",
        body: "ScheduleCreate"
      ),
      op(
        :get,
        "/topics/{id}/scheduled",
        ScheduledController,
        :index,
        "read",
        {:list, "Scheduled"},
        "The user's scheduled messages there."
      ),
      op(
        :delete,
        "/scheduled/{id}",
        ScheduledController,
        :delete,
        "write",
        :no_content,
        "Cancels a scheduled message."
      ),
      op(
        :get,
        "/forward-targets",
        MessageController,
        :forward_targets,
        "read",
        {:list, "ForwardTarget"},
        "Topics and conversations to forward to.",
        query: [{"q", "string", "Search."}, {"except", "string", "A topic to leave out."}]
      ),

      # Around messages
      op(
        :put,
        "/messages/{id}/reactions/{emoji}",
        MessageController,
        :react,
        "write",
        {:list, "Reaction"},
        "Adds a reaction (`agree`, `+1`, `:tada:`)."
      ),
      op(
        :delete,
        "/messages/{id}/reactions/{emoji}",
        MessageController,
        :unreact,
        "write",
        {:list, "Reaction"},
        "Takes a reaction back."
      ),
      op(
        :get,
        "/messages/{id}/reactions",
        MessageController,
        :reactions,
        "read",
        {:list, "Reactor"},
        "Who reacted with what."
      ),
      op(
        :post,
        "/topics/{id}/polls",
        PollController,
        :create,
        "write",
        "Message",
        "A poll under the user's message, or on its own.",
        body: "PollCreate"
      ),
      op(
        :put,
        "/polls/{id}/vote",
        PollController,
        :vote,
        "write",
        "Poll",
        "Votes, changes or takes back (`option_ids: []`) a vote.",
        body: "Vote"
      ),
      op(
        :post,
        "/topics/{id}/plugins/{command}",
        PluginController,
        :create,
        "write",
        "Message",
        "A plugin's block, as plugin_submit.",
        body: "PluginRun"
      ),
      op(
        :get,
        "/topics/{id}/plugins/{command}/forums",
        PluginController,
        :forums,
        "read",
        {:list, "ForumEntry"},
        "The !forum plugin's directory search.",
        query: [{"q", "string", "Search."}]
      ),
      op(
        :post,
        "/uploads",
        UploadController,
        :create,
        "write",
        "Upload",
        "Uploads an image (multipart `image`), as the composer does.",
        multipart: true
      ),
      op(
        :post,
        "/messages/{id}/report",
        MessageController,
        :report,
        "write",
        :no_content,
        "Reports a message to the moderators (MO-01).",
        body: "Report"
      ),
      op(
        :put,
        "/users/{id}/ignore",
        UserController,
        :ignore,
        "write",
        "UserCard",
        "Ignores a user (AC-06)."
      ),
      op(
        :delete,
        "/users/{id}/ignore",
        UserController,
        :unignore,
        "write",
        "UserCard",
        "Stops ignoring a user."
      ),
      op(
        :get,
        "/automessages",
        AutomessageController,
        :index,
        "read",
        {:list, "Automessage"},
        "Automessages the user may post in a topic.",
        query: [{"topic_id", "string", "The topic."}]
      ),
      op(
        :post,
        "/topics/{id}/automessages/{name}",
        AutomessageController,
        :create,
        "write",
        "Message",
        "Posts an automessage."
      ),

      # Private conversations
      op(
        :get,
        "/conversations",
        ConversationController,
        :index,
        "private",
        {:list, "Conversation"},
        "The user's private conversations."
      ),
      op(
        :post,
        "/conversations",
        ConversationController,
        :create,
        "private",
        "Conversation",
        "Starts or finds the conversation with someone.",
        body: "ConversationCreate"
      ),
      op(
        :get,
        "/conversations/{id}",
        ConversationController,
        :show,
        "private",
        "Conversation",
        "A conversation."
      ),
      op(
        :get,
        "/conversations/{id}/messages",
        ConversationController,
        :messages,
        "private",
        "MessageWindow",
        "Its messages, as for a topic.",
        query:
          @page ++
            [
              {"around", "string", "A message id."},
              {"first_unread", "boolean", "Land on the first unread."}
            ]
      ),
      op(
        :get,
        "/conversations/{id}/changes",
        ConversationController,
        :changes,
        "private",
        "Changes",
        "Changes since a cursor.",
        query: [{"since", "integer", "Cursor."}, {"limit", "integer", "1 to 100."}],
        req: "AP-16"
      ),
      op(
        :get,
        "/conversations/{id}/composer",
        ConversationController,
        :composer,
        "private",
        "Composer",
        "The composer's state (no slow mode).",
        req: "AP-14"
      ),
      op(
        :post,
        "/conversations/{id}/composer/typing",
        ConversationController,
        :typing,
        "private",
        "Composer",
        "The author started typing.",
        body: "Typing",
        req: "AP-14"
      ),
      op(
        :post,
        "/conversations/{id}/composer/commit",
        ConversationController,
        :commit,
        "private",
        "CommitResult",
        "Enter, Ctrl+Enter or a new message.",
        body: "Commit",
        req: "AP-14"
      ),

      # Moderation (AP-13)
      op(
        :get,
        "/moderation/reports",
        ModerationController,
        :reports,
        "moderate",
        {:list, "ReportGroup"},
        "Open reports of the categories the user moderates.",
        req: "AP-13"
      ),
      op(
        :patch,
        "/moderation/reports/{id}",
        ModerationController,
        :handle_report,
        "moderate",
        :no_content,
        "Resolves or dismisses a message's reports (`delete` for a private one).",
        body: "ReportOutcome",
        req: "AP-13"
      ),
      op(
        :get,
        "/moderation/pending-topics",
        ModerationController,
        :pending,
        "moderate",
        {:list, "PendingTopic"},
        "Topics waiting for approval (MO-04).",
        req: "AP-13"
      ),
      op(
        :post,
        "/moderation/pending-topics/{id}/approve",
        ModerationController,
        :approve,
        "moderate",
        "TopicCreated",
        "Approves a waiting topic.",
        req: "AP-13"
      ),
      op(
        :post,
        "/moderation/pending-topics/{id}/reject",
        ModerationController,
        :reject,
        "moderate",
        :no_content,
        "Rejects a waiting topic, with a reason.",
        body: "Reason",
        req: "AP-13"
      ),
      op(
        :get,
        "/moderation/log",
        ModerationController,
        :log,
        "moderate",
        {:page, "LogEntry"},
        "The moderation log (MO-03).",
        query: @page,
        req: "AP-13"
      ),
      op(
        :get,
        "/topics/{id}/moderation",
        ModerationController,
        :topic,
        "moderate",
        "TopicModeration",
        "Followers, move and unarchive targets of a topic.",
        req: "AP-13"
      ),
      op(
        :get,
        "/topics/{id}/permissions",
        ModerationController,
        :topic_permissions,
        "moderate",
        "TopicPermissions",
        "What each role may do in the topic: its own setting or the category's.",
        req: "AP-13"
      ),
      op(
        :put,
        "/topics/{id}/permissions",
        ModerationController,
        :set_topic_permissions,
        "moderate",
        "TopicPermissions",
        "Sets roles' rights in the topic: `allow`, `deny` or `unset` (the category's). Logged.",
        body: "TopicPermissionsUpdate",
        req: "AP-13"
      ),
      op(
        :post,
        "/topics/{id}/lock",
        ModerationController,
        :lock,
        "moderate",
        "Topic",
        "Locks a topic.",
        body: "Reason",
        req: "AP-13"
      ),
      op(
        :post,
        "/topics/{id}/unlock",
        ModerationController,
        :unlock,
        "moderate",
        "Topic",
        "Unlocks a topic.",
        body: "Reason",
        req: "AP-13"
      ),
      op(
        :post,
        "/topics/{id}/pin",
        ModerationController,
        :pin,
        "moderate",
        "Topic",
        "Pins a topic.",
        body: "Reason",
        req: "AP-13"
      ),
      op(
        :post,
        "/topics/{id}/unpin",
        ModerationController,
        :unpin,
        "moderate",
        "Topic",
        "Unpins a topic.",
        body: "Reason",
        req: "AP-13"
      ),
      op(
        :post,
        "/topics/{id}/archive",
        ModerationController,
        :archive,
        "moderate",
        "Topic",
        "Archives a topic.",
        body: "Reason",
        req: "AP-13"
      ),
      op(
        :post,
        "/topics/{id}/unarchive",
        ModerationController,
        :unarchive,
        "moderate",
        "Topic",
        "Unarchives a topic, to where it came from or `category_id`.",
        body: "Unarchive",
        req: "AP-13"
      ),
      op(
        :post,
        "/topics/{id}/move",
        ModerationController,
        :move,
        "moderate",
        "Topic",
        "Moves a topic to another category.",
        body: "Move",
        req: "AP-13"
      ),
      op(
        :post,
        "/topics/{id}/mark-inactive",
        ModerationController,
        :mark_inactive,
        "moderate",
        "Topic",
        "Marks a topic inactive.",
        req: "AP-13"
      ),
      op(
        :put,
        "/topics/{id}/icon",
        ModerationController,
        :icon,
        "moderate",
        "Topic",
        "Changes a topical topic's icon (`icon_id`, null for none).",
        body: "Icon",
        req: "AP-13"
      ),
      op(
        :post,
        "/topics/{id}/make-topical",
        ModerationController,
        :make_topical,
        "moderate",
        "Topic",
        "Makes a user topic's opening message topical.",
        body: "Icon",
        req: "AP-13"
      ),
      op(
        :put,
        "/topics/{id}/followed-by-everyone",
        ModerationController,
        :autofollow,
        "moderate",
        "Topic",
        "Everyone follows it (owners and administrators).",
        req: "AP-13"
      ),
      op(
        :delete,
        "/topics/{id}/followed-by-everyone",
        ModerationController,
        :unautofollow,
        "moderate",
        "Topic",
        "Stops making everyone follow it.",
        req: "AP-13"
      ),
      op(
        :delete,
        "/topics/{id}",
        ModerationController,
        :delete_topic,
        "moderate",
        :no_content,
        "Deletes a topic for good (`confirm: true`).",
        body: "DeleteTopic",
        req: "AP-13"
      ),
      op(
        :get,
        "/topic-icons",
        ModerationController,
        :topic_icons,
        "moderate",
        {:list, "TopicIcon"},
        "Topic icons to choose from.",
        req: "AP-13"
      ),
      op(
        :get,
        "/moderation/move-targets",
        ModerationController,
        :move_targets,
        "moderate",
        {:list, "Topic"},
        "Topics to move messages into.",
        query: [
          {"q", "string", "Title or link."},
          {"topic_id", "string", "The source, left out."}
        ],
        req: "AP-13"
      ),
      op(
        :post,
        "/moderation/messages/move",
        ModerationController,
        :move_messages,
        "moderate",
        "Topic",
        "Moves messages to a new or existing topic.",
        body: "MoveMessages",
        req: "AP-13"
      ),
      op(
        :post,
        "/moderation/messages/delete",
        ModerationController,
        :delete_messages,
        "moderate",
        :no_content,
        "Deletes several messages of a topic.",
        body: "DeleteMessages",
        req: "AP-13"
      ),
      op(
        :delete,
        "/moderation/messages/{id}",
        ModerationController,
        :delete_message,
        "moderate",
        "Message",
        "Deletes a message as a moderator.",
        body: "Reason",
        req: "AP-13"
      ),
      op(
        :put,
        "/moderation/messages/{id}",
        ModerationController,
        :edit_message,
        "moderate",
        "Message",
        "Edits someone's message as a moderator.",
        body: "ModeratorEdit",
        req: "AP-13"
      ),
      op(
        :post,
        "/moderation/messages/{id}/close",
        ModerationController,
        :close_message,
        "moderate",
        "Message",
        "Closes someone's open message (GM-16).",
        body: "Reason",
        req: "AP-13"
      ),
      op(
        :post,
        "/users/{id}/warn",
        ModerationController,
        :warn,
        "moderate",
        "Warning",
        "Warns a message's author.",
        body: "Warn",
        req: "AP-13"
      ),
      op(
        :get,
        "/users/{id}/warnings",
        ModerationController,
        :warnings,
        "moderate",
        {:list, "Warning"},
        "The user's earlier warnings the moderator may see.",
        req: "AP-13"
      ),
      op(
        :post,
        "/users/{id}/ban",
        ModerationController,
        :ban,
        "moderate",
        "UserCard",
        "Bans an account (server moderators).",
        body: "Ban",
        req: "AP-13"
      ),
      op(
        :delete,
        "/users/{id}/ban",
        ModerationController,
        :unban,
        "moderate",
        "UserCard",
        "Lifts a ban.",
        body: "Reason",
        req: "AP-13"
      )
    ]
  end

  @doc "The operation a route leads to, by its controller and action."
  @spec find(module(), atom()) :: op() | nil
  def find(controller, action), do: Map.get(by_action(), {controller, action})

  defp by_action do
    case :persistent_term.get({__MODULE__, :by_action}, nil) do
      nil ->
        map = Map.new(all(), &{{&1.controller, &1.action}, &1})
        :persistent_term.put({__MODULE__, :by_action}, map)
        map

      map ->
        map
    end
  end

  @doc "The path as the router writes it: `{id}` becomes `:id`."
  @spec router_path(String.t()) :: String.t()
  def router_path(path), do: Regex.replace(~r/\{(\w+)\}/, path, ":\\1")
end

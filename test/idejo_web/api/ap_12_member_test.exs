# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AP12MemberTest do
  @moduledoc """
  AP-11, AP-12: what a member does in the web app, through the API, with the same context
  functions: each answer checked against the database the web path would leave.
  """
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query
  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures
  import IdejoWeb.ApiHelpers

  alias Idejo.{Accounts, Conversations, Forum, Messages, Plugins, Reactions, Reading, Repo}
  alias Idejo.Messages.{Message, Polls, ScheduledMessage}
  alias Idejo.Moderation.Report

  setup do
    world = IdejoWeb.ApiWorld.build()
    {token, _row} = api_token_fixture(world.member)

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    Map.put(world, :token, token)
  end

  defp api(ctx, method, path, body \\ %{}),
    do:
      build_conn()
      |> api_conn(ctx.token)
      |> Phoenix.ConnTest.dispatch(@endpoint, method, path, body)

  @tag req: "AP-11"
  test "AP-11 a message is Markdown with structured objects, never HTML", ctx do
    {:ok, upload} = Idejo.Uploads.store_image(ctx.other, image_file(:png, width: 40, height: 30))

    body =
      "Hi @#{ctx.member.username} see #garden-plans and /general $none ||secret|| " <>
        "![pic](/uploads/#{upload.path})"

    {:ok, message} =
      Forum.post_message(ctx.other, ctx.topic, %{"body" => body, "reply_to_id" => ctx.message.id})

    {:ok, _} = Messages.set_spoiler(ctx.other, message, true, "Book 3")
    {:ok, _} = Reactions.toggle(ctx.member, message, "tada")

    map = api(ctx, :get, "/api/v1/messages/#{message.id}") |> api_json(200)
    refute Jason.encode!(map) =~ "<p>"
    assert map["body_md"] == body

    assert %{"type" => "user", "id" => member_id, "text" => "@" <> _} =
             Enum.find(map["mentions"], &(&1["type"] == "user"))

    assert member_id == ctx.member.id
    assert Enum.find(map["mentions"], &(&1["type"] == "topic"))["id"] == ctx.topic.id
    assert Enum.find(map["mentions"], &(&1["type"] == "category"))["id"] == ctx.general.id

    # Where each stands in the Markdown, as written there, ignoring case.
    assert Enum.map(map["mentions"], &{&1["type"], &1["source"]}) == [
             {"user", "@" <> String.downcase(ctx.member.username)},
             {"topic", "#garden-plans"},
             {"category", "/general"}
           ]

    for %{"source" => source} <- map["mentions"],
        do: assert(String.downcase(body) =~ source)

    assert [%{"upload_id" => upload_id, "width" => 40, "height" => 30}] = map["images"]
    assert upload_id == upload.id
    assert map["spoiler"] == %{"overlay" => "Book 3"}
    assert map["inline_spoilers"]
    assert [%{"message_id" => replied, "excerpt" => "Tomatoes"}] = map["replies_to"]
    assert replied == ctx.message.id
    assert [%{"name" => "tada", "count" => 1, "mine" => true}] = map["reactions"]
    assert map["author"]["display_name"] == ctx.other.display_name
    refute Map.has_key?(map["author"], "email")
  end

  @tag req: "AP-11"
  test "AP-11 a deleted message keeps its place; its text only for moderators", ctx do
    {:ok, _} = Messages.delete_as_moderator(ctx.admin, ctx.message, "spam")
    map = api(ctx, :get, "/api/v1/messages/#{ctx.message.id}") |> api_json(200)
    assert map["state"] == "deleted"
    assert map["deleted_by"] == "moderator"
    assert map["body_md"] == nil
    assert map["mentions"] == [] and map["images"] == []

    {admin_token, _} = api_token_fixture(ctx.admin)

    seen =
      build_conn()
      |> api_conn(admin_token)
      |> get(~p"/api/v1/messages/#{ctx.message.id}")
      |> api_json(200)

    assert seen["body_md"] == "Tomatoes"
  end

  @tag req: "AP-12"
  test "AP-12 the server, the account and its choices", ctx do
    server = api(ctx, :get, "/api/v1/server") |> api_json(200)
    assert server["settings"]["gm_window_seconds"] == 15
    assert server["settings"]["gm_early_reply"] == true

    me =
      api(ctx, :patch, "/api/v1/me", %{
        "display_name" => "Mia",
        "user_tag" => "gardener",
        "bio_md" => "I *grow*",
        "accepts_private_messages" => false
      })
      |> api_json(200)

    assert me["display_name"] == "Mia" and me["user_tag"] == "gardener" and
             me["bio_md"] == "I *grow*"

    user = Accounts.get_user!(ctx.member.id)
    assert user.display_name == "Mia"
    assert user.bio_html =~ "<em>grow</em>"
    refute user.accepts_private_messages

    invalid = api(ctx, :patch, "/api/v1/me", %{"display_name" => ""}) |> api_json(422)
    assert invalid["error"]["details"]["fields"]["display_name"]

    avatar =
      build_conn()
      |> api_conn(ctx.token)
      |> put(~p"/api/v1/me/avatar", %{
        "image" => %Plug.Upload{
          path: image_file(:png),
          filename: "me.png",
          content_type: "image/png"
        }
      })
      |> api_json(200)

    assert avatar["avatar_url"] =~ "/uploads/"
    assert api(ctx, :delete, "/api/v1/me/avatar") |> api_json(200) |> Map.get("avatar_url") == nil

    settings =
      api(ctx, :patch, "/api/v1/me/notification-settings", %{
        "email" => %{"followed_topics" => true},
        "push" => %{"followed" => false}
      })
      |> api_json(200)

    assert settings["email"]["followed_topics"] and settings["push"]["followed"] == false
    refute Idejo.Push.preferences(user).followed

    assert api(ctx, :post, "/api/v1/me/welcome") |> api_json(200) |> Map.get("welcomed")
    assert_intro(ctx, user)
    assert api(ctx, :get, "/api/v1/me/communities") |> api_json(200) == %{"data" => []}
    assert api(ctx, :post, "/api/v1/me/warnings/acknowledge") |> api_json(204)
  end

  @tag req: "AP-12"
  test "AP-12 the password changes, and every device signs in again", ctx do
    wrong =
      api(ctx, :put, "/api/v1/me/password", %{
        "current_password" => "nope",
        "password" => "a new password 1"
      })

    assert api_json(wrong, 422)["error"]["code"] == "validation"

    ok =
      api(ctx, :put, "/api/v1/me/password", %{
        "current_password" => valid_user_password(),
        "password" => "a new password 1",
        "password_confirmation" => "a new password 1"
      })

    assert api_json(ok, 204)
    assert {:error, :invalid} = Accounts.get_user_by_api_token(ctx.token)
  end

  @tag req: "AP-12"
  test "AP-12 browsing: categories, topics, tags, Unread, search, suggestions, emoji, users",
       ctx do
    categories = api(ctx, :get, "/api/v1/categories") |> api_json(200)
    ids = Enum.map(categories["data"], & &1["id"])
    assert ctx.general.id in ids
    refute ctx.hidden.id in ids
    general = Enum.find(categories["data"], &(&1["id"] == ctx.general.id))
    assert general["permissions"]["post"] and not general["permissions"]["moderate"]

    topics =
      api(ctx, :get, "/api/v1/categories/#{ctx.general.id}/topics?expanded=true") |> api_json(200)

    assert [%{"id" => id, "preview" => %{"first_excerpt" => "Hello"}}] = topics["data"]
    assert id == ctx.topic.id

    assert api(ctx, :get, "/api/v1/topics/active")
           |> api_json(200)
           |> Map.get("data")
           |> Enum.map(& &1["id"]) == [ctx.topic.id]

    # The home page's Expanded view, as the category's (BR-03 of the app).
    expanded =
      api(ctx, :get, "/api/v1/topics/active?expanded=true") |> api_json(200) |> Map.get("data")

    assert [%{"preview" => %{"first_excerpt" => "Hello"}}] = expanded
    plain = api(ctx, :get, "/api/v1/topics/active") |> api_json(200) |> Map.get("data")
    refute Map.has_key?(hd(plain), "preview")

    assert api(ctx, :get, "/api/v1/tags") |> api_json(200)

    unread = api(ctx, :get, "/api/v1/unread") |> api_json(200)
    assert unread["counter"]["count"] == 0

    hits = api(ctx, :get, "/api/v1/search?q=Tomatoes") |> api_json(200)
    assert [%{"message_id" => hit}] = hits["data"]
    assert hit == ctx.message.id
    assert api(ctx, :get, "/api/v1/search?q=Hush") |> api_json(200) |> Map.get("data") == []

    suggestions = api(ctx, :get, "/api/v1/suggest?sigil=%23&q=garden") |> api_json(200)
    assert Enum.any?(suggestions["data"], &(&1["insert"] == "garden-plans"))
    assert api(ctx, :get, "/api/v1/suggest?sigil=x") |> api_json(400)

    assert api(ctx, :get, "/api/v1/emoji?q=tada")
           |> api_json(200)
           |> Map.get("data")
           |> Enum.any?(&(&1["name"] == "tada"))

    assert api(ctx, :get, "/api/v1/gifs") |> api_json(200) |> Map.get("enabled") == false

    card = api(ctx, :get, "/api/v1/users/#{ctx.other.id}") |> api_json(200)
    assert card["display_name"] == ctx.other.display_name
    refute Map.has_key?(card, "email")

    assert api(ctx, :get, "/api/v1/roles/moderator") |> api_json(200) |> Map.get("name") ==
             "moderator"
  end

  @tag req: "AP-12"
  test "AP-12 topics: start one, title, follow, mute, read, mark unread, the window", ctx do
    created =
      api(ctx, :post, "/api/v1/categories/#{ctx.general.id}/topics", %{
        "title" => "Seeds",
        "body_md" => "Who has seeds?"
      })
      |> api_json(200)

    topic_id = created["topic"]["id"]
    assert created["topic"]["followed"]

    assert api(ctx, :post, "/api/v1/categories/#{ctx.hidden.id}/topics", %{
             "title" => "x",
             "body_md" => "y"
           })
           |> api_json(404)

    renamed =
      api(ctx, :patch, "/api/v1/topics/#{topic_id}", %{"title" => "Seed swap"}) |> api_json(200)

    assert renamed["title"] == "Seed swap"

    assert api(ctx, :patch, "/api/v1/topics/#{ctx.topic.id}", %{"title" => "Mine now"})
           |> api_json(403)

    assert api(ctx, :put, "/api/v1/topics/#{ctx.topic.id}/follow")
           |> api_json(200)
           |> Map.get("followed")

    refute api(ctx, :delete, "/api/v1/topics/#{ctx.topic.id}/follow")
           |> api_json(200)
           |> Map.get("followed")

    assert api(ctx, :put, "/api/v1/topics/#{ctx.topic.id}/mute")
           |> api_json(200)
           |> Map.get("muted")

    refute api(ctx, :delete, "/api/v1/topics/#{ctx.topic.id}/mute")
           |> api_json(200)
           |> Map.get("muted")

    {:ok, later} = Forum.post_message(ctx.other, ctx.topic, %{"body" => "Later"})

    assert api(ctx, :get, "/api/v1/topics/#{ctx.topic.id}")
           |> api_json(200)
           |> Map.get("unread_count") > 0

    api(ctx, :put, "/api/v1/topics/#{ctx.topic.id}/read", %{"message_id" => ctx.message.id})
    |> api_json(200)

    assert Reading.unread_counts(ctx.member, [ctx.topic.id])[ctx.topic.id] == 1

    assert api(ctx, :put, "/api/v1/topics/#{ctx.topic.id}/read")
           |> api_json(200)
           |> Map.get("unread_count") == 0

    assert api(ctx, :post, "/api/v1/topics/#{ctx.topic.id}/mark-unread")
           |> api_json(200)
           |> Map.get("unread_count") == 1

    window = api(ctx, :get, "/api/v1/topics/#{ctx.topic.id}/messages") |> api_json(200)
    assert Enum.map(window["data"], & &1["id"]) == [ctx.opening.id, ctx.message.id, later.id]
    assert window["first_message"]["id"] == ctx.opening.id
    assert window["first_unread"]["message_id"] == later.id

    small = api(ctx, :get, "/api/v1/topics/#{ctx.topic.id}/messages?limit=1") |> api_json(200)
    assert Enum.map(small["data"], & &1["id"]) == [later.id]

    earlier =
      api(
        ctx,
        :get,
        "/api/v1/topics/#{ctx.topic.id}/messages?limit=1&cursor=#{small["prev_cursor"]}"
      )
      |> api_json(200)

    assert Enum.map(earlier["data"], & &1["id"]) == [ctx.message.id]

    around =
      api(ctx, :get, "/api/v1/topics/#{ctx.topic.id}/messages?around=#{ctx.message.id}")
      |> api_json(200)

    assert ctx.message.id in Enum.map(around["data"], & &1["id"])

    assert api(ctx, :get, "/api/v1/topics/#{ctx.topic.id}/commands")
           |> api_json(200)
           |> Map.get("data")
           |> Enum.any?(&(&1["name"] == "poll"))
  end

  @tag req: "AP-12"
  test "AP-12 around messages: spoilers, polls, reactions, reports, forwards, new topics", ctx do
    %{"message" => %{"id" => mine}} =
      api(ctx, :post, "/api/v1/topics/#{ctx.topic.id}/composer/commit", %{"body_md" => "My plan"})
      |> api_json(200)

    assert api(ctx, :put, "/api/v1/messages/#{mine}/spoiler", %{"overlay" => "Plot"})
           |> api_json(200)
           |> Map.get("spoiler") == %{"overlay" => "Plot"}

    assert Repo.get!(Message, mine).spoiler_label == "Plot"

    assert api(ctx, :delete, "/api/v1/messages/#{mine}/spoiler")
           |> api_json(200)
           |> Map.get("spoiler") == nil

    assert api(ctx, :put, "/api/v1/messages/#{ctx.message.id}/spoiler") |> api_json(403)

    poll =
      api(ctx, :post, "/api/v1/topics/#{ctx.topic.id}/polls", %{
        "message_id" => mine,
        "question" => "When?",
        "options" => [%{"text" => "Sat"}, %{"text" => "Sun", "emoji" => "sunny"}],
        "hours" => 2
      })
      |> api_json(200)

    %{"id" => poll_id, "options" => [%{"id" => sat} | _]} = poll["poll"]

    voted =
      api(ctx, :put, "/api/v1/polls/#{poll_id}/vote", %{"option_ids" => [sat]}) |> api_json(200)

    assert voted["my_votes"] == [sat] and voted["total"] == 1
    assert Polls.summary(mine).votes[ctx.member.id] == [sat]

    added = api(ctx, :put, "/api/v1/messages/#{ctx.message.id}/reactions/:tada:") |> api_json(200)

    assert [
             %{
               "emoji" => ":tada:",
               "name" => "tada",
               "count" => 1,
               "mine" => true,
               "image_url" => "http" <> _
             }
           ] = added["data"]

    # PUT again changes nothing; DELETE takes it back.
    assert api(ctx, :put, "/api/v1/messages/#{ctx.message.id}/reactions/tada")
           |> api_json(200)
           |> Map.get("data")
           |> hd()
           |> Map.get("count") == 1

    assert [%{"emoji" => [":tada:"]}] =
             api(ctx, :get, "/api/v1/messages/#{ctx.message.id}/reactions")
             |> api_json(200)
             |> Map.get("data")

    assert api(ctx, :delete, "/api/v1/messages/#{ctx.message.id}/reactions/tada")
           |> api_json(200)
           |> Map.get("data") == []

    assert api(ctx, :post, "/api/v1/messages/#{ctx.message.id}/report", %{"reason" => "Rude"})
           |> api_json(204)

    assert Repo.exists?(
             from r in Report,
               where: r.message_id == ^ctx.message.id and r.reporter_id == ^ctx.member.id
           )

    assert api(ctx, :post, "/api/v1/messages/#{mine}/report", %{"reason" => "Me"})
           |> api_json(403)

    targets = api(ctx, :get, "/api/v1/forward-targets?q=Garden") |> api_json(200)
    assert is_list(targets["data"])

    fork =
      api(ctx, :post, "/api/v1/messages/#{ctx.message.id}/new-topic", %{
        "title" => "About tomatoes",
        "category_id" => ctx.general.id,
        "body_md" => "Let us talk"
      })
      |> api_json(200)

    assert Forum.get_viewable_topic(ctx.member, fork["topic"]["id"]).forked_from_message_id ==
             ctx.message.id

    assert fork["topic"]["continues_from"] == %{"message_id" => ctx.message.id}

    assert api(ctx, :get, "/api/v1/messages/#{ctx.message.id}/versions") |> api_json(403)
  end

  @tag req: "AP-12"
  test "AP-12 a forward, scheduled messages, uploads, ignoring and automessages", ctx do
    {:ok, other_topic} =
      Forum.create_topic(ctx.member, ctx.general, %{"title" => "Elsewhere", "body" => "Here"})

    forwarded =
      api(ctx, :post, "/api/v1/topics/#{other_topic.id}/composer/commit", %{
        "body_md" => "Look",
        "forward_of" => ctx.message.id
      })
      |> api_json(200)

    assert forwarded["message"]["forwarded_from"]["message_id"] == ctx.message.id
    assert forwarded["message"]["forwarded_from"]["visible"]

    scheduled =
      api(ctx, :post, "/api/v1/topics/#{ctx.topic.id}/scheduled", %{
        "body_md" => "Later on",
        "hours" => 0.5
      })
      |> api_json(200)

    assert [%{"id" => id}] =
             api(ctx, :get, "/api/v1/topics/#{ctx.topic.id}/scheduled")
             |> api_json(200)
             |> Map.get("data")

    assert id == scheduled["id"]

    assert api(ctx, :post, "/api/v1/topics/#{ctx.topic.id}/scheduled", %{
             "body_md" => "x",
             "hours" => 500
           })
           |> api_json(422)

    assert api(ctx, :delete, "/api/v1/scheduled/#{id}") |> api_json(204)
    refute Repo.get(ScheduledMessage, id)

    upload =
      build_conn()
      |> api_conn(ctx.token)
      |> post(~p"/api/v1/uploads", %{
        "image" => %Plug.Upload{
          path: image_file(:jpg),
          filename: "garden photo.jpg",
          content_type: "image/jpeg"
        }
      })
      |> api_json(200)

    assert upload["markdown"] == "![garden photo](/uploads/#{upload["upload_id"]}.jpg)"

    refute File.read!(
             Path.join(
               Application.fetch_env!(:idejo, :uploads_dir),
               upload["upload_id"] <> ".jpg"
             )
           ) =~ "Secret Person"

    assert build_conn()
           |> api_conn(ctx.token)
           |> post(~p"/api/v1/uploads", %{
             "image" => %Plug.Upload{path: raw_file("x.txt", "hello"), filename: "x.txt"}
           })
           |> api_json(422)

    assert api(ctx, :put, "/api/v1/users/#{ctx.other.id}/ignore")
           |> api_json(200)
           |> Map.get("ignored_by_me")

    assert Accounts.ignoring?(ctx.member, ctx.other)

    assert [%{"id" => ignored}] =
             api(ctx, :get, "/api/v1/me/ignored") |> api_json(200) |> Map.get("data")

    assert ignored == ctx.other.id
    window = api(ctx, :get, "/api/v1/topics/#{ctx.topic.id}/messages") |> api_json(200)
    assert Enum.all?(window["data"], &(&1["author"]["ignored_by_me"] == true))

    refute api(ctx, :delete, "/api/v1/users/#{ctx.other.id}/ignore")
           |> api_json(200)
           |> Map.get("ignored_by_me")

    commands = api(ctx, :get, "/api/v1/automessages?topic_id=#{ctx.topic.id}") |> api_json(200)
    assert is_list(commands["data"])

    assert api(ctx, :post, "/api/v1/topics/#{ctx.topic.id}/automessages/no-such-command")
           |> api_json(403)
  end

  @tag req: "AP-12"
  test "AP-12 plugins, through the same refusals as the web's form", ctx do
    File.rm_rf!(Plugins.dir())
    File.mkdir_p!(Plugins.dir())
    on_exit(fn -> File.rm_rf!(Plugins.dir()) end)
    Plugins.seed()

    assert api(ctx, :post, "/api/v1/topics/#{ctx.topic.id}/plugins/button", %{
             "params" => %{"label" => "Go", "url" => "https://example.org"}
           })
           |> api_json(403)

    {:ok, _} = Plugins.set_enabled(ctx.admin, "button", true)
    {:ok, _} = Plugins.set_roles(ctx.admin, "button", [Idejo.Access.built_in_role!(:member).id])

    message =
      api(ctx, :post, "/api/v1/topics/#{ctx.topic.id}/plugins/button", %{
        "params" => %{"label" => "Go", "url" => "https://example.org"}
      })
      |> api_json(200)

    assert [%{"command" => "button", "block" => "button", "params" => params}] =
             message["plugins"]

    refute Map.has_key?(params, "body_html")

    assert api(ctx, :post, "/api/v1/topics/#{ctx.topic.id}/plugins/button", %{
             "params" => %{"label" => "Go", "url" => "ftp://x"}
           })
           |> api_json(422)
  end

  @tag req: "AP-12"
  test "AP-12 private conversations: start, list, write, read; refused when turned off", ctx do
    {:ok, _} =
      Accounts.update_user_private_messages(ctx.admin, %{"accepts_private_messages" => false})

    assert api(ctx, :post, "/api/v1/conversations", %{"user_id" => ctx.admin.id}) |> api_json(403)

    started =
      api(ctx, :post, "/api/v1/conversations", %{"user_id" => ctx.other.id}) |> api_json(200)

    id = started["id"]

    assert [%{"id" => ^id}] =
             api(ctx, :get, "/api/v1/conversations") |> api_json(200) |> Map.get("data")

    assert Conversations.participant?(ctx.member, Forum.get_readable_topic(ctx.member, id))

    state = api(ctx, :get, "/api/v1/conversations/#{id}/composer") |> api_json(200)
    assert state["window_seconds"] == 0

    api(ctx, :post, "/api/v1/conversations/#{id}/composer/commit", %{"body_md" => "Hi"})
    |> api_json(200)

    # No slow mode: Ctrl+Enter completes it at once.
    sent =
      api(ctx, :post, "/api/v1/conversations/#{id}/composer/commit", %{
        "body_md" => "Hi",
        "break" => true
      })
      |> api_json(200)

    assert sent["message"]["state"] == "closed"
    refute sent["message"]["held"]

    assert api(ctx, :get, "/api/v1/conversations/#{id}/messages")
           |> api_json(200)
           |> Map.get("first_message") == nil

    # Never in search, categories or Unread.
    assert api(ctx, :get, "/api/v1/search?q=Hi") |> api_json(200) |> Map.get("data") == []
    assert api(ctx, :get, "/api/v1/conversations/#{ctx.conversation.id}") |> api_json(404)
  end

  # Getting started: due after a sign-in once welcomed; closed until the next one, or for good.
  defp assert_intro(ctx, user) do
    due? = fn -> api(ctx, :get, "/api/v1/me") |> api_json(200) |> Map.fetch!("intro_due") end

    {:ok, _user} = Idejo.Accounts.intro_on_sign_in(Idejo.Accounts.get_user!(user.id))
    assert due?.()
    refute api(ctx, :post, "/api/v1/me/intro") |> api_json(200) |> Map.get("intro_due")

    {:ok, _user} = Idejo.Accounts.intro_on_sign_in(Idejo.Accounts.get_user!(user.id))
    assert due?.()
    api(ctx, :post, "/api/v1/me/intro", %{"hide" => true}) |> api_json(200)
    {:ok, _user} = Idejo.Accounts.intro_on_sign_in(Idejo.Accounts.get_user!(user.id))
    refute due?.()
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AP15EventsTest do
  @moduledoc "AP-15, AP-16: the app's socket, its channels, and catch-up after a disconnect."
  use IdejoWeb.ConnCase, async: false

  import IdejoWeb.ApiHelpers
  import Phoenix.ChannelTest, except: [connect: 2]
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]

  alias Idejo.{Access, Accounts, Forum, Messages, Reactions}
  alias Idejo.Accounts.ApiTokens
  alias Idejo.Messages.{Authors, Polls}
  alias IdejoWeb.Api.Revocations

  @endpoint IdejoWeb.Endpoint

  setup do
    world = IdejoWeb.ApiWorld.build()
    {member_token, member_row} = api_token_fixture(world.member)
    {other_token, _row} = api_token_fixture(world.other)

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    Map.merge(world, %{
      member_token: member_token,
      member_row: member_row,
      other_token: other_token
    })
  end

  defp socket!(token) do
    {:ok, socket} = Phoenix.ChannelTest.connect(IdejoWeb.ApiSocket, %{"token" => token})
    socket
  end

  @tag req: "AP-15"
  test "AP-15 the socket takes a valid token in its params, nothing else", %{member_token: token} do
    assert {:ok, _socket} = Phoenix.ChannelTest.connect(IdejoWeb.ApiSocket, %{"token" => token})

    assert {:error, :unauthenticated} =
             Phoenix.ChannelTest.connect(IdejoWeb.ApiSocket, %{"token" => "idj_nope"})

    assert {:error, :unauthenticated} = Phoenix.ChannelTest.connect(IdejoWeb.ApiSocket, %{})
  end

  @tag req: "AP-15"
  test "AP-15 each event of a growing message reaches another member with the object", ctx do
    socket = socket!(ctx.member_token)

    {:ok, reply, _channel} =
      subscribe_and_join(socket, IdejoWeb.TopicChannel, "topic:" <> ctx.topic.id)

    assert is_integer(reply["cursor"])

    {:ok, opened} = Messages.commit(ctx.other, ctx.topic, "Hello")

    assert_push "message.opened", %{
      "message" => %{"id" => id, "state" => "open"},
      "cursor" => cursor
    }

    assert id == opened.id and is_integer(cursor)

    {:ok, _} = Messages.commit(ctx.other, ctx.topic, "Hello. More")
    assert_push "message.appended", %{"message" => %{"body_md" => "Hello. More."}}

    {:ok, _} = Messages.commit(ctx.other, ctx.topic, "Changed. More")
    assert_push "message.edited", %{"message" => %{"body_md" => "Changed. More."}}

    {:ok, _} = Messages.commit(ctx.other, ctx.topic, "Changed. More. End", break: true)
    assert_push "message.closed", %{"message" => %{"state" => "closed"}}

    {:ok, _} =
      Reactions.toggle(ctx.admin, Forum.get_readable_message(ctx.admin, opened.id), "tada")

    assert_push "reaction.changed", %{
      "message_id" => ^id,
      "reactions" => [%{"name" => "tada", "count" => 1}]
    }

    {:ok, _} =
      Messages.delete_as_moderator(ctx.admin, Forum.get_readable_message(ctx.admin, opened.id))

    assert_push "message.deleted", %{"message" => %{"state" => "deleted", "body_md" => nil}}

    {:ok, _} =
      Forum.moderate_topic(ctx.admin, Forum.get_viewable_topic(ctx.admin, ctx.topic.id), :pin)

    assert_push "topic.updated", %{"pinned" => true}
  end

  @tag req: "AP-15"
  test "AP-15 a poll's update carries counts as the member may see them", ctx do
    socket = socket!(ctx.member_token)

    {:ok, _, _channel} =
      subscribe_and_join(socket, IdejoWeb.TopicChannel, "topic:" <> ctx.topic.id)

    {:ok, message, _summary} =
      Polls.post(ctx.other, ctx.topic, %{
        "question" => "Which?",
        "options" => ["A", "B"],
        "hours" => "1"
      })

    assert_push "poll.updated", %{"poll" => %{"question" => "Which?", "total" => nil}}
    summary = Polls.summary(message.id)
    {:ok, _} = Polls.vote(ctx.admin, message, [hd(summary.options).id])
    assert_push "poll.updated", %{"poll" => poll}
    refute Map.has_key?(poll, "voters")
  end

  @tag req: "AP-15"
  test "AP-15 joining a topic or category without the view right is refused", ctx do
    socket = socket!(ctx.member_token)

    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(socket, IdejoWeb.TopicChannel, "topic:" <> ctx.secret.id)

    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(socket, IdejoWeb.CategoryChannel, "category:" <> ctx.hidden.id)

    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(
               socket,
               IdejoWeb.TopicChannel,
               "conversation:" <> ctx.conversation.id
             )
  end

  @tag req: "AP-15"
  test "AP-15 losing the view right removes the member", ctx do
    socket = socket!(ctx.member_token)

    {:ok, _, channel} =
      subscribe_and_join(socket, IdejoWeb.TopicChannel, "topic:" <> ctx.topic.id)

    Process.monitor(channel.channel_pid)

    member_role = Enum.find(Access.list_roles(), &(&1.name == "member"))
    {:ok, _} = Access.set_permission(ctx.admin, member_role, ctx.general, :view, :deny)
    guest = Enum.find(Access.list_roles(), &(&1.name == "guest"))
    {:ok, _} = Access.set_permission(ctx.admin, guest, ctx.general, :view, :deny)

    assert_push "forbidden", %{"reason" => "forbidden"}
    assert_receive {:DOWN, _, :process, _, _}
  end

  @tag req: "AP-15"
  test "AP-15 a private conversation's events reach its participants only", ctx do
    socket = socket!(ctx.other_token)

    {:ok, _, _channel} =
      subscribe_and_join(socket, IdejoWeb.TopicChannel, "conversation:" <> ctx.conversation.id)

    {:ok, _} = Messages.commit(ctx.other, ctx.conversation, "Just us")
    assert_push "message.opened", %{"message" => %{"body_md" => "Just us."}}

    # The member is not in it: no join, so nothing.
    member = socket!(ctx.member_token)

    assert {:error, _} =
             subscribe_and_join(
               member,
               IdejoWeb.TopicChannel,
               "conversation:" <> ctx.conversation.id
             )

    assert {:error, _} =
             subscribe_and_join(member, IdejoWeb.TopicChannel, "topic:" <> ctx.conversation.id)
  end

  @tag req: "AP-15"
  test "AP-15 typing is accepted from the client and never broadcast", ctx do
    socket = socket!(ctx.member_token)

    {:ok, _, channel} =
      subscribe_and_join(socket, IdejoWeb.TopicChannel, "topic:" <> ctx.topic.id)

    watcher = socket!(ctx.other_token)
    {:ok, _, _} = subscribe_and_join(watcher, IdejoWeb.TopicChannel, "topic:" <> ctx.topic.id)

    ref = Phoenix.ChannelTest.push(channel, "typing", %{"typing" => true})
    assert_reply ref, :ok
    refute_push "typing", _
    refute_receive %Phoenix.Socket.Message{event: "typing"}
    assert Messages.composer(ctx.member, ctx.topic).typing_since
  end

  @tag req: "AP-15"
  test "AP-15 while the topic channel is joined, the member counts as viewing it (PN-08)", ctx do
    socket = socket!(ctx.member_token)
    refute Authors.present?(ctx.topic.id, ctx.member.id)

    {:ok, _, _channel} =
      subscribe_and_join(socket, IdejoWeb.TopicChannel, "topic:" <> ctx.topic.id)

    assert Authors.present?(ctx.topic.id, ctx.member.id)
  end

  @tag req: "AP-15"
  test "AP-15 the user channel brings notifications, the counter and a revoked token", ctx do
    socket = socket!(ctx.member_token)
    {:ok, reply, _channel} = subscribe_and_join(socket, IdejoWeb.UserChannel, "user:me")
    assert reply["unread"]["count"] == 0

    {:ok, _} =
      Forum.post_message(ctx.other, ctx.topic, %{"body" => "Hey @#{ctx.member.username}"})

    assert_push "notification", %{"kind" => "mention", "topic_id" => topic_id}
    assert topic_id == ctx.topic.id
    assert_push "unread.changed", %{"count" => 1, "level" => "mention"}

    :ok = ApiTokens.revoke(ctx.member, ctx.member_row.id)
    assert_push "token.revoked", %{"token_id" => _}
  end

  @tag req: "AP-15"
  test "AP-15 the category channel tells of new topics and activity", ctx do
    socket = socket!(ctx.member_token)

    {:ok, _, _channel} =
      subscribe_and_join(socket, IdejoWeb.CategoryChannel, "category:" <> ctx.general.id)

    {:ok, topic} =
      Forum.create_topic(ctx.other, ctx.general, %{"title" => "New one", "body" => "First"})

    assert_push "topic.created", %{"title" => "New one"}

    {:ok, _} = Messages.commit(ctx.other, topic, "A new message")
    assert_push "topic.activity", %{"topic_id" => id, "messages_count" => 2}
    assert id == topic.id
  end

  @tag req: "AP-15"
  test "AP-15 revoking the token closes its socket", ctx do
    socket = socket!(ctx.member_token)
    {:ok, _, channel} = subscribe_and_join(socket, IdejoWeb.UserChannel, "user:me")
    @endpoint.subscribe(Revocations.socket_id(ctx.member_row.id))

    {:ok, _} = Accounts.ban_for(ctx.admin, ctx.member, :forever, nil)
    assert_push "token.revoked", _
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}, 1_000
    _ = channel
  end

  @tag req: "AP-16"
  test "AP-16 catch-up returns exactly the changes missed, in order", ctx do
    token = ctx.member_token

    cursor =
      build_conn()
      |> api_conn(token)
      |> get(~p"/api/v1/topics/#{ctx.topic.id}/messages")
      |> api_json(200)
      |> Map.fetch!("cursor")

    # Disconnected meanwhile: a message opens, grows, another closes, one gets a reaction.
    {:ok, a} = Messages.commit(ctx.other, ctx.topic, "One")
    {:ok, _} = Messages.commit(ctx.other, ctx.topic, "One. Two")
    {:ok, b} = Forum.post_message(ctx.admin, ctx.topic, %{"body" => "Admin here"})

    {:ok, _} =
      Reactions.toggle(ctx.admin, Forum.get_readable_message(ctx.admin, ctx.message.id), "tada")

    changes =
      build_conn()
      |> api_conn(token)
      |> get(~p"/api/v1/topics/#{ctx.topic.id}/changes?since=#{cursor}")
      |> api_json(200)

    ids = Enum.map(changes["data"], & &1["id"])
    assert ids == [a.id, b.id, ctx.message.id]
    assert Enum.find(changes["data"], &(&1["id"] == a.id))["body_md"] == "One. Two."
    refute changes["more"]

    # Nothing since the new cursor.
    again =
      build_conn()
      |> api_conn(token)
      |> get(~p"/api/v1/topics/#{ctx.topic.id}/changes?since=#{changes["cursor"]}")
      |> api_json(200)

    assert again["data"] == []
    assert again["cursor"] == changes["cursor"]

    # Pages, oldest change first.
    paged =
      build_conn()
      |> api_conn(token)
      |> get(~p"/api/v1/topics/#{ctx.topic.id}/changes?since=#{cursor}&limit=2")
      |> api_json(200)

    assert Enum.map(paged["data"], & &1["id"]) == [a.id, b.id]
    assert paged["more"]

    # A cursor from the future (a restored backup): reload.
    expired =
      build_conn()
      |> api_conn(token)
      |> get(~p"/api/v1/topics/#{ctx.topic.id}/changes?since=#{changes["cursor"] + 1_000_000}")
      |> api_json(410)

    assert expired["error"]["code"] == "cursor_expired"
  end
end

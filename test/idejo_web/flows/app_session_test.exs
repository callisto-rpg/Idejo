# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Flows.AppSessionTest do
  @moduledoc """
  The official app's session, end to end (AP-07 to AP-20): discovery, sign-in through the
  forum's pages with PKCE, reading, a growing message over the API while another member's
  channel watches it, reactions, a poll, a report, catch-up after a disconnect,
  UnifiedPush, and signing out.
  """
  use IdejoWeb.ConnCase, async: false
  use Oban.Testing, repo: Idejo.Repo

  import Idejo.AccountsFixtures
  import IdejoWeb.ApiHelpers
  import Phoenix.ChannelTest, except: [connect: 2]
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]

  alias Idejo.{FakePushService, Forum, Messages}
  alias Idejo.Messages.Polls

  @endpoint IdejoWeb.Endpoint

  setup do
    FakePushService.start!()

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    :ok
  end

  @tag flow: "app-session"
  test "a member uses the app from sign-in to sign-out", %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    other = user_fixture(%{display_name: "Ola"})

    {:ok, topic} =
      Forum.create_topic(other, general, %{"title" => "Garden plans", "body" => "Saturday?"})

    {:ok, poll_message, _} =
      Polls.post(other, topic, %{
        "question" => "Which day?",
        "options" => ["Sat", "Sun"],
        "hours" => "2"
      })

    member = user_fixture(%{display_name: "Mia"})

    # 1. Discovery.
    discovery = conn |> get(~p"/.well-known/idejo") |> json_response(200)
    assert discovery["oauth"]["authorize"] == "/app/authorize"

    # 2. Sign-in in the browser: the sign-in page, then the confirmation, then Allow.
    {verifier, challenge} = pkce()
    params = authorize_params(challenge, %{"device_name" => "Mia's Pixel"})
    visitor = get(conn, ~p"/app/authorize?#{params}")
    assert redirected_to(visitor) == ~p"/users/sign-in"

    signed_in =
      visitor
      |> recycle()
      |> post(~p"/users/sign-in", %{
        "user" => %{"email" => member.email, "password" => valid_user_password()}
      })

    back = redirected_to(signed_in)
    assert back =~ "/app/authorize?"
    browser = recycle(signed_in)
    assert browser |> get(back) |> html_response(200) =~ "Mia&#39;s Pixel"

    callback =
      browser |> post(~p"/app/authorize", Map.put(params, "choice", "allow")) |> redirected_to()

    %{"code" => code, "state" => "xyz"} =
      callback |> URI.parse() |> Map.get(:query) |> URI.decode_query()

    # 3. The token.
    grant =
      build_conn()
      |> post(~p"/api/v1/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => "org.idejo.app:/oauth/callback",
        "client_id" => "org.idejo.app",
        "code_verifier" => verifier
      })
      |> api_json(200)

    token = grant["access_token"]

    api = fn method, path, body ->
      build_conn() |> api_conn(token) |> dispatch(@endpoint, method, path, body)
    end

    # 4. Reading.
    [%{"id" => category_id}] =
      api.(:get, "/api/v1/categories", %{}) |> api_json(200) |> Map.get("data")

    assert category_id == general.id
    window = api.(:get, "/api/v1/topics/#{topic.id}/messages", %{}) |> api_json(200)
    cursor = window["cursor"]

    # 5. Another member watches the topic.
    {other_token, _} = api_token_fixture(other)

    {:ok, other_socket} =
      Phoenix.ChannelTest.connect(IdejoWeb.ApiSocket, %{"token" => other_token})

    {:ok, _, _} = subscribe_and_join(other_socket, IdejoWeb.TopicChannel, "topic:" <> topic.id)

    # 6. Mia's app joins, types, and grows a message: Enter three times, then Ctrl+Enter.
    {:ok, socket} = Phoenix.ChannelTest.connect(IdejoWeb.ApiSocket, %{"token" => token})
    {:ok, _, channel} = subscribe_and_join(socket, IdejoWeb.TopicChannel, "topic:" <> topic.id)
    ref = Phoenix.ChannelTest.push(channel, "typing", %{"typing" => true})
    assert_reply ref, :ok

    commit = fn body, break ->
      api.(:post, "/api/v1/topics/#{topic.id}/composer/commit", %{
        "body_md" => body,
        "break" => break
      })
      |> api_json(200)
    end

    %{"message" => %{"id" => id}} = commit.("Saturday works", false)
    assert_push "message.opened", %{"message" => %{"id" => ^id}}
    commit.("Saturday works. I bring seeds", false)
    assert_push "message.appended", %{"message" => %{"id" => ^id}}
    commit.("Saturday works. I bring seeds. And tea", false)
    assert_push "message.appended", %{"message" => %{"id" => ^id}}
    done = commit.("Saturday works. I bring seeds. And tea. See you", true)
    assert done["message"]["state"] == "closed"

    assert_push "message.closed", %{
      "message" => %{"id" => ^id, "body_md" => "Saturday works. I bring seeds. And tea. See you."}
    }

    # 7. A reaction, a vote, a report.
    api.(:put, "/api/v1/messages/#{poll_message.id}/reactions/agree", %{}) |> api_json(200)
    assert_push "reaction.changed", %{"message_id" => _}
    %{id: poll_id, options: [sat | _]} = Polls.summary(poll_message.id)

    assert api.(:put, "/api/v1/polls/#{poll_id}/vote", %{"option_ids" => [sat.id]})
           |> api_json(200)
           |> Map.get("my_votes") == [sat.id]

    assert api.(:post, "/api/v1/messages/#{poll_message.id}/report", %{"reason" => "Testing"})
           |> api_json(204)

    # 8. A disconnect; meanwhile Ola writes. Catch-up brings exactly that and what came before.
    Process.unlink(channel.channel_pid)
    close(channel)
    {:ok, missed} = Messages.commit(other, topic, "Great, see you")

    changes =
      api.(:get, "/api/v1/topics/#{topic.id}/changes?since=#{cursor}", %{}) |> api_json(200)

    assert List.last(changes["data"])["id"] == missed.id
    assert id in Enum.map(changes["data"], & &1["id"])

    # 9. UnifiedPush.
    {public, _private} = :crypto.generate_key(:ecdh, :prime256v1)

    registered =
      api.(:post, "/api/v1/me/push/unifiedpush", %{
        "endpoint" => "https://up.example.net/UP?t=1",
        "p256dh" => Base.url_encode64(public, padding: false),
        "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
        "device_name" => "Mia's Pixel"
      })
      |> api_json(200)

    assert registered["kind"] == "unifiedpush"

    # 10. Sign out: the token and its push registration end.
    assert api.(:post, "/api/v1/oauth/revoke", %{}) |> api_json(204)
    assert api.(:get, "/api/v1/me", %{}) |> api_json(401)
    assert api.(:get, "/api/v1/me/push", %{}) |> api_json(401)
    assert Idejo.Push.list_subscriptions(member) == []
  end
end

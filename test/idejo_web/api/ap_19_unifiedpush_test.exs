# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AP19UnifiedPushTest do
  @moduledoc """
  AP-19: the app's UnifiedPush endpoint, registered with Web Push keys, gets the same
  pushes as a browser, on any public https host, checked at registration and at every send.
  """
  use IdejoWeb.ConnCase, async: false
  use Oban.Testing, repo: Idejo.Repo

  import Idejo.AccountsFixtures
  import IdejoWeb.ApiHelpers
  import Phoenix.ChannelTest, only: [subscribe_and_join: 3]

  alias Idejo.Accounts.ApiTokens
  alias Idejo.{FakeDNS, FakePushService, Forum, Push, Repo}
  alias Idejo.Push.{Crypto, Dispatch, Subscription, Worker}

  @endpoint IdejoWeb.Endpoint

  setup do
    on_exit(&FakeDNS.reset/0)
    user = user_fixture()
    {token, row} = api_token_fixture(user)
    %{user: user, token: token, row: row, service: FakePushService.start!()}
  end

  defp keys do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)
    auth = :crypto.strong_rand_bytes(16)
    %{public: public, private: private, auth: auth}
  end

  defp register(token, endpoint, keys \\ keys()) do
    build_conn()
    |> api_conn(token)
    |> post(~p"/api/v1/me/push/unifiedpush", %{
      "endpoint" => endpoint,
      "p256dh" => Base.url_encode64(keys.public, padding: false),
      "auth" => Base.url_encode64(keys.auth, padding: false),
      "device_name" => "Pixel"
    })
  end

  @tag req: "AP-19"
  test "AP-19 any public https host registers; no allowlist", %{token: token, row: row} do
    body = register(token, "https://up.example.net/UP?token=abc") |> api_json(200)
    assert body["kind"] == "unifiedpush"
    assert body["name"] == "Pixel"
    assert body["this_device"]

    subscription = Repo.get!(Subscription, body["id"])
    assert subscription.api_token_id == row.id
    assert subscription.session_id == nil
    refute Push.Endpoint.allowed?("up.example.net")

    list = build_conn() |> api_conn(token) |> get(~p"/api/v1/me/push") |> api_json(200)
    assert [%{"kind" => "unifiedpush"}] = list["data"]
  end

  @tag req: "AP-19"
  test "AP-19 http, other ports, private, loopback, link-local, CGNAT and mapped addresses are refused",
       %{token: token} do
    for {endpoint, code} <- [
          {"http://up.example.net/UP", "not_https"},
          {"https://up.example.net:8443/UP", "not_https"},
          {"https://user:pass@up.example.net/UP", "validation"},
          {"https://private.example.net/UP", "private_address"},
          {"https://loopback.example.net/UP", "private_address"},
          {"https://linklocal.example.net/UP", "private_address"},
          {"https://cgnat.example.net/UP", "private_address"},
          {"https://mapped.example.net/UP", "private_address"},
          {"https://ula.example.net/UP", "private_address"},
          {"https://multicast.example.net/UP", "private_address"},
          {"https://nowhere.example.net/UP", "unresolvable"}
        ] do
      body = register(token, endpoint) |> Map.get(:resp_body) |> Jason.decode!()
      assert body["error"]["code"] == code, "#{endpoint}: #{inspect(body)}"
    end

    assert Repo.aggregate(Subscription, :count) == 0
  end

  @tag req: "AP-19"
  test "AP-19 DNS that turns private between registration and send stops the send", %{
    token: token,
    user: user
  } do
    %{"id" => id} = register(token, "https://changing.example.net/UP") |> api_json(200)
    FakeDNS.answer("changing.example.net", [{10, 0, 0, 1}])

    {:ok, 1} =
      Push.deliver(user, %{
        "web_push" => 8030,
        "notification" => %{"title" => "Hi", "navigate" => "https://idejo.test/"}
      })

    [job] = all_enqueued(worker: Worker)
    assert {:cancel, {:endpoint, :private_address}} = perform_job(Worker, job.args)
    refute_receive {:push_request, _}
    assert Repo.get(Subscription, id)
  end

  @tag req: "AP-19"
  test "AP-19 pushes are the browsers' payloads (PN-12), encrypted for the app", %{
    token: token,
    user: user
  } do
    keys = keys()
    register(token, "https://up.example.net/UP?x=1", keys) |> api_json(200)

    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    ada = user_fixture(%{display_name: "Ada"})

    {:ok, topic} =
      Forum.create_topic(ada, general, %{"title" => "Garden plans", "body" => "Saturday?"})

    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "Hey @#{user.username}"})

    for job <- all_enqueued(worker: Dispatch), do: perform_job(Dispatch, job.args)
    [job] = all_enqueued(worker: Worker)
    assert :ok = perform_job(Worker, job.args)

    assert_receive {:push_request, request}
    assert request.host == "up.example.net"
    {:ok, json} = Crypto.decrypt(request.body, keys.private, keys.public, keys.auth)
    payload = Jason.decode!(json)
    assert payload["web_push"] == 8030
    assert payload["notification"]["title"] == "Ada mentioned you in Garden plans"
    assert payload["notification"]["tag"] == "mentions"
    assert payload["notification"]["navigate"] =~ "/m/"
  end

  @tag req: "AP-19"
  test "AP-19 no push about a topic while its channel is joined (PN-08)", %{
    token: token,
    user: user
  } do
    register(token, "https://up.example.net/UP") |> api_json(200)
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    ada = user_fixture(%{display_name: "Ada"})

    {:ok, topic} =
      Forum.create_topic(ada, general, %{"title" => "Garden plans", "body" => "Saturday?"})

    {:ok, socket} = Phoenix.ChannelTest.connect(IdejoWeb.ApiSocket, %{"token" => token})
    {:ok, _, _} = subscribe_and_join(socket, IdejoWeb.TopicChannel, "topic:" <> topic.id)

    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "Hey @#{user.username}"})
    for job <- all_enqueued(worker: Dispatch), do: perform_job(Dispatch, job.args)
    assert all_enqueued(worker: Worker) == []
  end

  @tag req: "AP-19"
  test "AP-19 the registration ends with its token; ten per user, both kinds", %{
    token: token,
    user: user,
    row: row
  } do
    %{"id" => id} = register(token, "https://up.example.net/UP/one") |> api_json(200)
    :ok = ApiTokens.revoke(user, row.id)
    refute Repo.get(Subscription, id)

    {token, _row} = api_token_fixture(user)
    for i <- 1..11, do: register(token, "https://up.example.net/UP/#{i}") |> api_json(200)
    assert Repo.aggregate(Subscription, :count) == Push.max_per_user()
  end

  @tag req: "AP-19"
  test "AP-19 removing and testing", %{token: token} do
    %{"id" => id} = register(token, "https://up.example.net/UP") |> api_json(200)

    assert build_conn() |> api_conn(token) |> post(~p"/api/v1/me/push/test") |> api_json(200) ==
             %{"queued" => 1}

    assert build_conn()
           |> api_conn(token)
           |> delete(~p"/api/v1/me/push/unifiedpush/#{id}")
           |> api_json(204)

    assert build_conn()
           |> api_conn(token)
           |> delete(~p"/api/v1/me/push/unifiedpush/#{id}")
           |> api_json(404)
  end
end

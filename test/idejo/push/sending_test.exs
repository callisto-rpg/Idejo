# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.SendingTest do
  # Not async: the fake push service is set in the application environment, and some tests
  # change server-wide settings.
  use Idejo.DataCase, async: false
  use Oban.Testing, repo: Idejo.Repo

  import Idejo.AccountsFixtures

  alias Idejo.FakePushService
  alias Idejo.Push
  alias Idejo.Push.{Crypto, Endpoint, Sender, Subscription, Vapid, Worker}
  alias Idejo.Settings

  @payload %{
    "web_push" => 8030,
    "notification" => %{
      "title" => "Ada replied in Garden plans",
      "navigate" => "https://idejo.test/m/1"
    }
  }

  # A browser: its subscription saved for `user`, and its private key to read what it gets.
  defp browser(
         user,
         endpoint \\ "https://fcm.googleapis.com/fcm/send/#{System.unique_integer([:positive])}?x=1"
       ) do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)
    auth = :crypto.strong_rand_bytes(16)

    {:ok, subscription} =
      Push.subscribe(user, "session", %{
        "endpoint" => endpoint,
        "keys" => %{
          "p256dh" => Base.url_encode64(public, padding: false),
          "auth" => Base.url_encode64(auth, padding: false)
        }
      })

    %{subscription: subscription, public: public, private: private, auth: auth}
  end

  defp job(subscription, urgency \\ "normal") do
    %{
      "subscription_id" => subscription.id,
      "payload" => @payload,
      "ttl" => 86_400,
      "urgency" => urgency
    }
  end

  defp reload(subscription), do: Repo.get(Subscription, subscription.id)

  setup do
    %{service: FakePushService.start!()}
  end

  describe "deliver" do
    @tag req: "PN-15"
    test "PN-15 queues one job per browser of the user in the push queue" do
      user = user_fixture()
      one = browser(user)
      two = browser(user, "https://updates.push.services.mozilla.com/wpush/v2/def")
      browser(user_fixture())

      assert Push.deliver(user, @payload, urgency: "high") == {:ok, 2}

      for %{subscription: subscription} <- [one, two] do
        assert_enqueued(worker: Worker, queue: :push, args: job(subscription, "high"))
      end
    end

    @tag req: "PN-12"
    test "PN-12 a payload that would not stay under 3 KB encrypted is refused" do
      user = user_fixture()
      %{subscription: subscription} = browser(user)
      overhead = byte_size(Jason.encode!(%{"t" => ""}))
      at_limit = %{"t" => String.duplicate("x", Push.max_payload() - overhead)}

      assert Push.deliver(user, Map.put(at_limit, "t", at_limit["t"] <> "x")) ==
               {:error, :too_large}

      assert {:ok, 1} = Push.deliver(user, at_limit)

      {public, auth} = Subscription.keys(subscription)
      assert byte_size(Crypto.encrypt(Jason.encode!(at_limit), public, auth)) < 3072
    end

    @tag req: "PN-19"
    test "PN-19 nothing is queued or sent while push is off" do
      user = user_fixture()
      %{subscription: subscription} = browser(user)

      {:ok, _} =
        Settings.update_settings(user_with_role_fixture(:administrator), %{
          "push_enabled" => "off"
        })

      assert Push.deliver(user, @payload) == {:error, :disabled}
      assert perform_job(Worker, job(subscription)) == {:cancel, :disabled}
      refute_receive {:push_request, _}
    end
  end

  describe "the request (PN-15)" do
    @tag req: "PN-15"
    test "PN-15 sends the payload encrypted for the browser and signed with the server's VAPID key" do
      owner = user_with_role_fixture(:owner)
      user = user_fixture()
      %{subscription: subscription} = browser = browser(user)

      assert :ok = perform_job(Worker, job(subscription, "high"))

      assert_receive {:push_request, request}
      assert request.method == "POST"
      assert request.host == "fcm.googleapis.com"
      assert request.path == URI.parse(subscription.endpoint) |> then(&"#{&1.path}?#{&1.query}")
      assert request.headers["ttl"] == "86400"
      assert request.headers["urgency"] == "high"
      assert request.headers["content-encoding"] == "aes128gcm"

      assert {:ok, json} =
               Crypto.decrypt(request.body, browser.private, browser.public, browser.auth)

      assert Jason.decode!(json) == @payload

      "vapid t=" <> rest = request.headers["authorization"]
      [jwt, "k=" <> k] = String.split(rest, ", ")
      assert k == Vapid.public_key()
      [_head, claims, _signature] = String.split(jwt, ".")
      claims = claims |> Base.url_decode64!(padding: false) |> Jason.decode!()
      assert claims["aud"] == "https://fcm.googleapis.com"
      assert claims["sub"] == "mailto:" <> owner.email

      sent = reload(subscription)
      assert sent.last_success_at
      assert sent.failure_count == 0
    end

    @tag req: "PN-16"
    test "PN-16 connects to the address the check returned, keeping the host name for TLS" do
      {:ok, uri, addresses} = Endpoint.check("https://fcm.googleapis.com/fcm/send/abc")

      options = Sender.request_options(uri, addresses, nil)
      assert options[:url] == "https://142.250.74.10/fcm/send/abc"
      assert options[:headers] == [{"host", "fcm.googleapis.com"}]
      assert options[:connect_options][:hostname] == "fcm.googleapis.com"
      assert options[:redirect] == false

      ipv6 =
        Sender.request_options(%{uri | port: 8443}, [{0x2A00, 0x1450, 0, 0, 0, 0, 0, 1}], nil)

      assert ipv6[:url] == "https://[2a00:1450::1]:8443/fcm/send/abc"
      assert ipv6[:headers] == [{"host", "fcm.googleapis.com:8443"}]
    end

    @tag req: "PN-16"
    test "PN-16 an endpoint that no longer passes the check is not sent to" do
      admin = user_with_role_fixture(:administrator)
      %{subscription: subscription} = browser(user_fixture())
      {:ok, _} = Settings.update_settings(admin, %{"push_services" => "*.push.apple.com"})

      assert perform_job(Worker, job(subscription)) == {:cancel, {:endpoint, :not_allowed}}
      refute_receive {:push_request, _}
      assert reload(subscription)
    end
  end

  describe "answers" do
    @tag req: "PN-13"
    test "PN-13 a 404 or 410 deletes the subscription", %{service: service} do
      for status <- [404, 410] do
        %{subscription: subscription} = browser(user_fixture())
        FakePushService.respond(service, [{status, []}])

        assert :ok = perform_job(Worker, job(subscription))
        refute reload(subscription)
      end
    end

    @tag req: "PN-15"
    test "PN-15 429 and 5xx are tried again later, after Retry-After when given", %{
      service: service
    } do
      %{subscription: subscription} = browser(user_fixture())

      in_two_minutes =
        DateTime.utc_now() |> DateTime.add(120) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")

      FakePushService.respond(service, [
        {429, [{"retry-after", "600"}]},
        {503, []},
        {503, [{"retry-after", in_two_minutes}]}
      ])

      assert perform_job(Worker, job(subscription), attempt: 1) == {:snooze, 600}
      assert perform_job(Worker, job(subscription), attempt: 3) == {:snooze, 120}
      assert {:snooze, seconds} = perform_job(Worker, job(subscription), attempt: 1)
      assert seconds in 118..120
      assert reload(subscription).failure_count == 3

      # Exponential: 30 s doubled at each attempt, at most an hour.
      assert Enum.map(1..9, &Worker.delay(&1, nil)) == [
               30,
               60,
               120,
               240,
               480,
               960,
               1920,
               3600,
               3600
             ]
    end

    @tag req: "PN-13"
    test "PN-13 five failures in a row delete the subscription; a success resets the count", %{
      service: service
    } do
      %{subscription: subscription} = browser(user_fixture())
      FakePushService.respond(service, List.duplicate({500, []}, 4) ++ [{201, []}])

      for _ <- 1..4, do: assert({:snooze, _} = perform_job(Worker, job(subscription)))
      assert reload(subscription).failure_count == 4
      assert :ok = perform_job(Worker, job(subscription))
      assert reload(subscription).failure_count == 0

      FakePushService.respond(service, List.duplicate({500, []}, Worker.max_failures()))
      for _ <- 1..4, do: assert({:snooze, _} = perform_job(Worker, job(subscription)))
      assert perform_job(Worker, job(subscription)) == {:cancel, :too_many_failures}
      refute reload(subscription)
    end

    @tag req: "PN-15"
    test "PN-15 other errors are not tried again; no answer is", %{service: service} do
      %{subscription: subscription} = browser(user_fixture())
      FakePushService.respond(service, [{400, []}])

      assert perform_job(Worker, job(subscription)) == {:cancel, {:status, 400}}
      assert reload(subscription).failure_count == 1

      # Nothing listens on port 9 (discard) on the loopback.
      Application.put_env(:idejo, :push_target, "http://127.0.0.1:9")
      assert {:snooze, 30} = perform_job(Worker, job(subscription), attempt: 1)
      assert reload(subscription).failure_count == 2
    end

    @tag req: "PN-13"
    test "PN-13 a subscription deleted meanwhile is not sent to" do
      %{subscription: subscription} = browser(user_fixture())

      :ok =
        Push.unsubscribe(
          Repo.get!(Idejo.Accounts.User, subscription.user_id),
          subscription.endpoint
        )

      assert perform_job(Worker, job(subscription)) == {:cancel, :unsubscribed}
      refute_receive {:push_request, _}
    end
  end
end

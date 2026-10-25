# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.FollowedTest do
  # Not async: a test changes a server-wide setting.
  use Idejo.DataCase, async: false
  use Oban.Testing, repo: Idejo.Repo

  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages.Authors
  alias Idejo.Push
  alias Idejo.Push.{FollowedWorker, Worker}
  alias Idejo.Reading
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    reader =
      user_fixture()
      |> Ecto.Changeset.change(created_at: DateTime.add(DateTime.utc_now(:second), -3600))
      |> Repo.update!()

    browser(reader)
    ada = user_fixture(%{display_name: "Ada"})

    topics =
      for title <- ["Garden plans", "Seed swap", "Kitchen"] do
        {:ok, topic} = Forum.create_topic(ada, general, %{"title" => title, "body" => "Hi"})
        :ok = Reading.follow(reader, topic)
        :ok = Reading.mark_read(reader, topic)
        topic
      end

    Repo.delete_all(Oban.Job)
    %{admin: admin, reader: reader, ada: ada, topics: topics}
  end

  defp browser(user) do
    {public, _private} = :crypto.generate_key(:ecdh, :prime256v1)

    {:ok, _} =
      Push.subscribe(user, "session", %{
        "endpoint" => "https://fcm.googleapis.com/fcm/send/#{System.unique_integer([:positive])}",
        "keys" => %{
          "p256dh" => Base.url_encode64(public, padding: false),
          "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
        }
      })
  end

  defp post!(user, topic, body) do
    {:ok, message} = Forum.post_message(user, topic, %{"body" => body})
    message
  end

  # Runs the waiting followed-activity jobs, whenever they are due, and returns the titles
  # of the pushes they queued (and the jobs' results).
  defp run do
    results =
      for job <- all_enqueued(worker: FollowedWorker) do
        result = perform_job(FollowedWorker, job.args)
        Repo.delete!(job)
        result
      end

    titles = for job <- all_enqueued(worker: Worker), do: job.args["payload"]["notification"]
    Repo.delete_all(Oban.Job)
    {titles, results}
  end

  # Time passes: the last push and every notification so far are `minutes` older.
  defp time_passes(minutes) do
    for table <- ~w(notifications push_preferences) do
      column = if table == "notifications", do: "created_at", else: "followed_sent_at"

      Repo.query!(
        "UPDATE #{table} SET #{column} = #{column} - make_interval(mins => $1)",
        [minutes]
      )
    end
  end

  @tag req: "PN-04"
  test "PN-04 new messages in followed topics: one push counting the topics, the Unread page",
       %{reader: reader, ada: ada, topics: [garden, seeds, _kitchen]} do
    post!(ada, garden, "Beans")
    post!(ada, garden, "And peas")
    post!(user_fixture(), seeds, "Swap on Sunday")

    # One job waiting per user, however many messages.
    assert [job] = all_enqueued(worker: FollowedWorker)
    assert job.args == %{"user_id" => reader.id}

    assert {[notification], [:ok]} = run()

    assert notification["title"] == "There are new messages in 2 topics you follow"
    assert notification["body"] == ""
    assert notification["tag"] == "followed"
    assert notification["navigate"] =~ ~r{/unread$}
    assert Push.preferences(reader).followed_count == 2
  end

  @tag req: "PN-04"
  test "PN-04 at most one per interval, and only when a topic has news since the last", %{
    admin: admin,
    reader: reader,
    ada: ada,
    topics: [garden, seeds, kitchen]
  } do
    post!(ada, garden, "Beans")
    assert {[_], _} = run()

    # Within the interval: due at its end, and too early if run before.
    post!(ada, seeds, "Swap")
    assert [job] = all_enqueued(worker: FollowedWorker)
    assert DateTime.diff(job.scheduled_at, DateTime.utc_now(), :minute) in 29..30
    assert {[], [{:snooze, seconds}]} = run()
    assert seconds > 29 * 60

    # Past it: the news in Seed swap makes it 2 topics.
    time_passes(31)
    post!(ada, seeds, "Sunday")
    assert {[notification], _} = run()
    assert notification["title"] == "There are new messages in 2 topics you follow"

    # Nothing new since: nothing, however many topics are still unread.
    time_passes(31)
    Oban.insert!(FollowedWorker.new(%{"user_id" => reader.id}))
    assert {[], [:ok]} = run()

    # The interval is a setting.
    {:ok, _} = Settings.update_settings(admin, %{"push_followed_interval_minutes" => "5"})
    time_passes(6)
    post!(ada, kitchen, "Soup")
    assert {[notification], _} = run()
    assert notification["title"] == "There are new messages in 3 topics you follow"
  end

  @tag req: "PN-05"
  test "PN-05 a mention or reply in a followed topic is not followed activity too", %{
    reader: reader,
    ada: ada,
    topics: [garden | _]
  } do
    post!(ada, garden, "Look, @#{reader.username}")
    assert all_enqueued(worker: FollowedWorker) == []
  end

  @tag req: "PN-08"
  test "PN-08 topics on screen are left out", %{
    reader: reader,
    ada: ada,
    topics: [garden, seeds, _]
  } do
    :ok = Authors.present(garden.id, reader.id)
    post!(ada, garden, "Beans")
    post!(ada, seeds, "Swap")
    assert {[notification], _} = run()
    assert notification["title"] == "There are new messages in 1 topic you follow"

    # Only the topic on screen has news: nothing.
    time_passes(31)
    post!(ada, garden, "Peas")
    assert {[], _} = run()
    :ok = Authors.absent(garden.id, reader.id, grace_ms: 3_600_000)
  end

  @tag req: "PN-11"
  test "PN-11 followed activity can be switched off; muted topics never count", %{
    reader: reader,
    ada: ada,
    topics: [garden, seeds, _]
  } do
    :ok = Reading.mute(reader, seeds)
    post!(ada, seeds, "Swap")
    assert all_enqueued(worker: FollowedWorker) == []

    {:ok, _} = Push.update_preferences(reader, %{"followed" => "false"})
    post!(ada, garden, "Beans")
    assert {[], [{:cancel, :switched_off}]} = run()
  end
end

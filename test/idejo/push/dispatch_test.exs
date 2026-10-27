# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.DispatchTest do
  # Not async: some tests change the server-wide push switch.
  use Idejo.DataCase, async: false
  use Oban.Testing, repo: Idejo.Repo

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Messages.Authors
  alias Idejo.Push
  alias Idejo.Push.{Dispatch, Payload, Worker}
  alias Idejo.Reading
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    reader =
      user_fixture(%{display_name: "Rea"})
      |> Ecto.Changeset.change(created_at: DateTime.add(DateTime.utc_now(:second), -3600))
      |> Repo.update!()

    browser(reader)
    ada = user_fixture(%{display_name: "Ada"})

    {:ok, topic} =
      Forum.create_topic(ada, general, %{"title" => "Garden plans", "body" => "Saturday?"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, reader: reader, ada: ada, topic: topic}
  end

  defp browser(user) do
    {public, _private} = :crypto.generate_key(:ecdh, :prime256v1)

    {:ok, subscription} =
      Push.subscribe(user, "session", %{
        "endpoint" => "https://fcm.googleapis.com/fcm/send/#{System.unique_integer([:positive])}",
        "keys" => %{
          "p256dh" => Base.url_encode64(public, padding: false),
          "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
        }
      })

    subscription
  end

  defp post!(user, topic, body, attrs \\ %{}) do
    {:ok, message} = Forum.post_message(user, topic, Map.put(attrs, "body", body))
    message
  end

  # Runs the queued dispatch jobs and returns the pushes they queued for browsers, in
  # order: `{payload, urgency}`.
  defp pushes do
    for job <- all_enqueued(worker: Dispatch) do
      perform_job(Dispatch, job.args)
      Repo.delete!(job)
    end

    sent =
      for job <- Enum.sort_by(all_enqueued(worker: Worker), & &1.id) do
        assert job.args["ttl"] == 86_400
        {job.args["payload"], job.args["urgency"]}
      end

    Repo.delete_all(Oban.Job)
    sent
  end

  defp notification(payload), do: payload["notification"]

  @tag req: "PN-01"
  test "PN-01 a reply pushes who replied, the excerpt and its permalink; several count", %{
    reader: reader,
    ada: ada,
    topic: topic
  } do
    mine = post!(reader, topic, "Tomatoes or beans?")
    assert pushes() == []

    reply = post!(ada, topic, "Beans, they **climb**.", %{"reply_to_id" => mine.id})
    assert [{payload, "normal"}] = pushes()

    assert notification(payload) == %{
             "title" => "Ada replied in Garden plans",
             "body" => "Beans, they climb.",
             "navigate" => Idejo.Federation.uri(:message, reply.id),
             "tag" => "reply-#{topic.id}",
             "lang" => "en"
           }

    # PN-12: declarative, with the badge of unread replies and mentions.
    assert payload["web_push"] == 8030
    assert payload["app_badge"] == 1

    post!(user_fixture(), topic, "Or both", %{"reply_to_id" => mine.id})
    assert [{payload, _}] = pushes()
    assert notification(payload)["title"] == "2 replies in Garden plans"
    assert notification(payload)["tag"] == "reply-#{topic.id}"
    assert payload["app_badge"] == 2
  end

  @tag req: "PN-02"
  test "PN-02 a mention pushes high; several open the Unread page, reading resets", %{
    general: general,
    reader: reader,
    ada: ada,
    topic: topic
  } do
    first = post!(ada, topic, "What do you think, @#{reader.username}?")
    assert [{payload, "high"}] = pushes()

    assert notification(payload) |> Map.take(~w(title navigate tag)) == %{
             "title" => "Ada mentioned you in Garden plans",
             "navigate" => Idejo.Federation.uri(:message, first.id),
             "tag" => "mentions"
           }

    {:ok, other} =
      Forum.create_topic(ada, general, %{
        "title" => "Seed swap",
        "body" => "Bring yours, @#{reader.username}"
      })

    assert [{payload, "high"}] = pushes()
    assert notification(payload)["title"] == "You have been mentioned 2 times"
    assert notification(payload)["body"] == "Seed swap · Garden plans"
    assert notification(payload)["navigate"] =~ ~r{/unread$}

    # Read: the count starts again.
    :ok = Reading.mark_read(reader, topic)
    :ok = Reading.mark_read(reader, other)
    post!(ada, topic, "Still there, @#{reader.username}?")
    assert [{payload, _}] = pushes()
    assert notification(payload)["title"] == "Ada mentioned you in Garden plans"
  end

  @tag req: "PN-03"
  test "PN-03 a +role mention names the role; several count, a message once", %{
    admin: admin,
    general: general,
    reader: reader,
    ada: ada,
    topic: topic
  } do
    {:ok, crew} =
      Access.create_role(admin, %{"name" => unique_role_name("Crew"), "mentionable" => "true"})

    {:ok, cooks} =
      Access.create_role(admin, %{"name" => unique_role_name("Cooks"), "mentionable" => "true"})

    :ok = Access.grant_role(reader, crew)
    :ok = Access.grant_role(reader, cooks)
    slug = Access.role_slug(crew)

    post!(ada, topic, "Hey +#{slug}")
    assert [{payload, "normal"}] = pushes()
    assert notification(payload)["title"] == "Ada mentioned +#{slug} in Garden plans"
    assert notification(payload)["tag"] == "role-mentions"

    # Both roles in one message count once.
    {:ok, _} =
      Forum.create_topic(ada, general, %{
        "title" => "Kitchen",
        "body" => "+#{slug} and +#{Access.role_slug(cooks)}"
      })

    assert [{payload, _}] = pushes()
    assert notification(payload)["title"] == "Your role has been tagged 2 times"
    assert notification(payload)["body"] == "Kitchen · Garden plans"
  end

  @tag req: "PN-05"
  test "PN-05 one push per user per growing message, the strongest kind when it is sent", %{
    admin: admin,
    reader: reader,
    ada: ada,
    topic: topic
  } do
    {:ok, crew} =
      Access.create_role(admin, %{"name" => unique_role_name("Crew"), "mentionable" => "true"})

    :ok = Access.grant_role(reader, crew)

    # Opened with a role mention, grown with an @mention before the push went: the mention.
    {:ok, _} = Messages.commit(ada, topic, "Hey +#{Access.role_slug(crew)}")

    {:ok, _} =
      Messages.commit(ada, topic, "Hey +#{Access.role_slug(crew)} and @#{reader.username}")

    assert [{payload, "high"}] = pushes()
    assert notification(payload)["tag"] == "mentions"

    # Pushed already: growing more pushes nothing.
    {:ok, _} = Messages.commit(ada, topic, "Hey all, @#{reader.username}, come")
    assert pushes() == []
  end

  @tag req: "PN-06"
  test "PN-06 an append pushes only for someone it newly mentions", %{
    reader: reader,
    ada: ada,
    topic: topic
  } do
    {:ok, _} = Messages.commit(ada, topic, "Thinking aloud")
    assert pushes() == []
    {:ok, _} = Messages.commit(ada, topic, "Thinking aloud. And you, @#{reader.username}?")
    assert [{payload, "high"}] = pushes()
    assert notification(payload)["title"] == "Ada mentioned you in Garden plans"
  end

  @tag req: "PN-07"
  test "PN-07 authors are never pushed about their own messages", %{reader: reader, topic: topic} do
    mine = post!(reader, topic, "Note to self, @#{reader.username}")
    post!(reader, topic, "Answering myself", %{"reply_to_id" => mine.id})
    assert pushes() == []
  end

  @tag req: "PN-08"
  test "PN-08 no push while the user has a live view of the topic", %{
    reader: reader,
    ada: ada,
    topic: topic
  } do
    :ok = Authors.present(topic.id, reader.id)
    post!(ada, topic, "Look, @#{reader.username}")
    assert pushes() == []
    :ok = Authors.absent(topic.id, reader.id, grace_ms: 3_600_000)
  end

  @tag req: "PN-09"
  test "PN-09 a topic muted before the push goes sends nothing", %{
    reader: reader,
    ada: ada,
    topic: topic
  } do
    post!(ada, topic, "Look, @#{reader.username}")
    :ok = Reading.mute(reader, topic)
    assert pushes() == []
  end

  @tag req: "PN-10"
  test "PN-10 view right, ban and deletion are checked again when the push goes", %{
    admin: admin,
    general: general,
    reader: reader,
    ada: ada,
    topic: topic
  } do
    # No longer allowed to view the category.
    post!(ada, topic, "Look, @#{reader.username}")
    member = Access.built_in_role!(:member)
    {:ok, _} = Access.set_permission(admin, member, general, :view, :deny)
    assert pushes() == []
    {:ok, _} = Access.set_permission(admin, member, general, :view, :unset)

    # Banned meanwhile.
    post!(ada, topic, "Again, @#{reader.username}")

    Repo.update_all(from(u in Idejo.Accounts.User, where: u.id == ^reader.id),
      set: [banned_at: DateTime.utc_now()]
    )

    assert pushes() == []

    Repo.update_all(from(u in Idejo.Accounts.User, where: u.id == ^reader.id),
      set: [banned_at: nil]
    )

    # Deleted by a moderator meanwhile.
    gone = post!(ada, topic, "Spam for @#{reader.username}")
    {:ok, _} = Messages.delete_as_moderator(admin, gone, "Spam")
    assert pushes() == []
  end

  @tag req: "PN-11"
  test "PN-11 each type can be switched off, for all the user's browsers", %{
    reader: reader,
    ada: ada,
    topic: topic
  } do
    assert Push.preferences(reader).reply
    {:ok, _} = Push.update_preferences(reader, %{"reply" => "false"})
    mine = post!(reader, topic, "Tomatoes?")
    post!(ada, topic, "Beans", %{"reply_to_id" => mine.id})
    assert pushes() == []

    post!(ada, topic, "But @#{reader.username}, beans")
    assert [{payload, _}] = pushes()
    assert notification(payload)["tag"] == "mentions"
  end

  @tag req: "PN-12"
  test "PN-12 nothing is queued without a browser, while push is off, or once read", %{
    admin: admin,
    reader: reader,
    ada: ada,
    topic: topic
  } do
    # No browser.
    other = user_fixture()
    post!(ada, topic, "Hello @#{other.username}")
    refute Enum.any?(all_enqueued(worker: Dispatch), &(&1.args["user_id"] == other.id))
    Repo.delete_all(Oban.Job)

    # Push off (PN-19).
    {:ok, _} = Settings.update_settings(admin, %{"push_enabled" => "off"})

    post!(ada, topic, "Hello @#{reader.username}")
    assert all_enqueued(worker: Dispatch) == []

    {:ok, _} = Settings.update_settings(admin, %{"push_enabled" => "on"})

    # The excerpt: plain text, at most 120 characters and "…".
    long = post!(ada, topic, String.duplicate("**word** ", 60))
    excerpt = Payload.excerpt(long)
    assert String.length(excerpt) <= 121
    assert String.ends_with?(excerpt, "…")
    refute excerpt =~ "*"
    Repo.delete_all(Oban.Job)

    # Read before the push went: nothing new to say.
    post!(ada, topic, "Once more @#{reader.username}")
    :ok = Reading.mark_read(reader, topic)
    assert pushes() == []
  end

  # Private conversations (steward decision, 2026-10-27).
  @tag req: "PN-01"
  test "PN-01 a private message pushes who wrote it; several read N new private messages", %{
    reader: reader,
    ada: ada
  } do
    {:ok, conversation} = Idejo.Conversations.start(ada, reader)
    first = post!(ada, conversation, "Are you **coming**?")
    assert [{payload, "high"}] = pushes()

    assert notification(payload) == %{
             "title" => "Ada sent you a private message",
             "body" => "Are you coming?",
             "navigate" => Idejo.Federation.uri(:message, first.id),
             "tag" => "private",
             "lang" => "en"
           }

    # Any kind in a private conversation: a reply, from another conversation too.
    bo = user_fixture(%{display_name: "Bo"})
    {:ok, other} = Idejo.Conversations.start(bo, reader)
    post!(bo, other, "Hi")
    assert [{one, _}] = pushes()
    assert notification(one)["title"] == "2 new private messages."
    post!(ada, conversation, "Hello?", %{"reply_to_id" => first.id})
    assert [{two, _}] = pushes()
    assert notification(two)["title"] == "3 new private messages."
    assert notification(two)["body"] == "Ada · Bo"
    assert notification(two)["navigate"] == Application.fetch_env!(:idejo, :base_uri) <> "/p"

    # Reading resets the count; a growing message counts once.
    :ok = Reading.mark_read(reader, conversation)
    :ok = Reading.mark_read(reader, other)
    {:ok, _} = Messages.commit(ada, conversation, "One")
    {:ok, _} = Messages.commit(ada, conversation, "One more")
    assert [{payload, _}] = pushes()
    assert notification(payload)["title"] == "Ada sent you a private message"

    # Nobody else is pushed, and the author never.
    outsider = user_fixture()
    browser(outsider)
    browser(ada)
    post!(reader, conversation, "Yes, @#{outsider.username} too")
    assert [{payload, _}] = pushes()
    assert notification(payload)["title"] == "Rea sent you a private message"
  end

  @tag req: "PN-11"
  test "PN-11 private messages have their own switch", %{reader: reader, ada: ada} do
    {:ok, conversation} = Idejo.Conversations.start(ada, reader)
    {:ok, _} = Push.update_preferences(reader, %{"followed" => "false", "reply" => "false"})
    post!(ada, conversation, "Still pushed")
    assert [_] = pushes()

    {:ok, _} = Push.update_preferences(reader, %{"private" => "false"})
    post!(ada, conversation, "Not pushed")
    assert pushes() == []
    assert all_enqueued(worker: Idejo.Push.FollowedWorker) == []
  end
end

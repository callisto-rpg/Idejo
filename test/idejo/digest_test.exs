# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The email summary (steward decision, 2026-10-23, with NO-04 of the v1 sheet).
defmodule Idejo.DigestTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Accounts.User
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Notifications.{Digest, EmailPreference}
  alias Idejo.Reading

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    ada = user_fixture(%{username: unique_username("ada"), display_name: "Ada"})
    bo = user_fixture(%{username: unique_username("bo"), display_name: "Bo"})
    {:ok, topic} = Forum.create_topic(ada, general, %{"title" => "Plans", "body" => "Tonight?"})

    # Everyone in this test was here a moment ago, except Ada, away since two days.
    Repo.update_all(User, set: [last_seen_at: DateTime.utc_now()])
    away!(ada, -2)

    %{admin: admin, general: general, ada: ada, bo: bo, topic: topic}
  end

  defp away!(user, days) do
    at = DateTime.add(DateTime.utc_now(), days, :day)
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [last_seen_at: at])
  end

  defp later(days), do: DateTime.add(DateTime.utc_now(), days, :day)

  defp sent_to(user),
    do: Enum.filter(sent(), &(&1.to == [{"", user.email}] and &1.subject =~ "What you missed"))

  defp sent do
    receive_all([])
  end

  defp receive_all(acc) do
    receive do
      {:email, email} -> receive_all([email | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "the defaults: mentions and replies, and topics one started; once a week", %{ada: ada} do
    preference = Digest.preferences(ada)
    assert preference.mentions and preference.own_topics and preference.once_a_week
    refute preference.role_mentions or preference.followed_topics
    refute preference.new_topics or preference.all_activity
  end

  test "after a day away, one email counts what was posted, with the week's note and unsubscribe",
       %{ada: ada, bo: bo, topic: topic} do
    [first] = Forum.list_messages(topic)
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Yes", "reply_to_id" => first.id})
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "@#{ada.username} and you?"})
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Bring snacks"})
    # Still being written: not counted (NO-04).
    {:ok, _} = Messages.commit(user_fixture(), topic, "Hmm")

    assert Digest.run() == 1
    assert [email] = sent_to(ada)
    assert email.subject =~ "What you missed on"
    assert email.text_body =~ "2 mentions of you and replies to your messages"
    assert email.text_body =~ "3 new messages in topics you started"
    assert email.text_body =~ "This is your last summary this week"
    assert email.text_body =~ "Profile and account, Email notifications"
    %EmailPreference{unsubscribe_token: token} = Repo.get!(EmailPreference, ada.id)
    assert email.text_body =~ "/email/unsubscribe/#{token}"
    assert email.headers["List-Unsubscribe"] =~ "/email/unsubscribe/#{token}"
    assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"

    # Bo was here: nothing for Bo. And Ada gets no second one this week.
    assert sent_to(bo) == []
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "More"})
    assert Digest.run(later(1)) == 0
    assert Digest.run(later(6)) == 0
    assert Digest.run(later(8)) == 1
  end

  test "without once a week, one a day while away; coming back starts again", %{
    ada: ada,
    bo: bo,
    topic: topic
  } do
    {:ok, _} = Digest.update_preferences(ada, %{"once_a_week" => "false"})
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "One"})
    assert Digest.run() == 1
    refute hd(sent_to(ada)).text_body =~ "this week"

    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Two"})
    assert Digest.run(later(1)) == 1
    # Nothing new since the last one: no email.
    assert Digest.run(later(2)) == 0

    # Back after the last summary, then away again for a day: a summary again.
    Repo.update_all(EmailPreference, set: [digest_sent_at: later(-3)])
    away!(ada, -2)
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Three"})
    assert Digest.run() == 1
  end

  test "only what was chosen; deleted messages and muted topics are left out", %{
    admin: admin,
    general: general,
    ada: ada,
    bo: bo,
    topic: topic
  } do
    {:ok, _} =
      Digest.update_preferences(ada, %{
        "mentions" => "false",
        "own_topics" => "false",
        "new_topics" => "true",
        "all_activity" => "true"
      })

    {:ok, spam} = Forum.post_message(bo, topic, %{"body" => "Spam"})
    {:ok, _} = Messages.delete_as_moderator(admin, spam, "Spam")
    {:ok, other} = Forum.create_topic(bo, general, %{"title" => "Elsewhere", "body" => "Hi"})
    {:ok, _} = Forum.post_message(bo, other, %{"body" => "Hello"})
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Here"})
    :ok = Reading.mute(ada, topic)

    assert Digest.run() == 1
    [email] = sent_to(ada)
    assert email.text_body =~ "1 new topic"
    # The opening message and Hello, in the topic not muted; not Here or the spam.
    assert email.text_body =~ "2 new messages in the forum"
    refute email.text_body =~ "topics you started"
  end

  test "nothing new, nothing chosen, unverified, banned or recently seen: no email", %{
    admin: admin,
    ada: ada,
    bo: bo,
    topic: topic
  } do
    assert Digest.run() == 0

    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Hi"})
    {:ok, _} = Idejo.Accounts.ban_user(admin, ada, later(7), "Rude")
    assert Digest.run() == 0
    {:ok, _} = Idejo.Accounts.unban_user(admin, Repo.reload!(ada))

    {:ok, _} = Digest.update_preferences(ada, %{"mentions" => "false", "own_topics" => "false"})
    assert Digest.run() == 0
    {:ok, _} = Digest.update_preferences(ada, %{"own_topics" => "true"})

    # Unverified, away and with something to count: no email either.
    Repo.update_all(from(u in User, where: u.id == ^ada.id), set: [confirmed_at: nil])
    assert Digest.run() == 0

    # Verified again and seen an hour ago: still nothing; a day later, the summary.
    Repo.update_all(from(u in User, where: u.id == ^ada.id),
      set: [
        confirmed_at: DateTime.utc_now(:second),
        last_seen_at: DateTime.add(DateTime.utc_now(), -1, :hour)
      ]
    )

    assert Digest.run() == 0
    assert Digest.run(later(1)) == 1
  end

  test "unsubscribe turns every summary off; an unknown token does nothing", %{
    ada: ada,
    bo: bo,
    topic: topic
  } do
    {:ok, _} = Forum.post_message(bo, topic, %{"body" => "Hi"})
    assert Digest.run() == 1
    token = Repo.get!(EmailPreference, ada.id).unsubscribe_token

    assert Digest.unsubscribe("nope") == :error
    assert Digest.unsubscribe(token) == :ok
    preference = Digest.preferences(ada)
    refute Enum.any?(EmailPreference.options(), &Map.fetch!(preference, &1))
  end

  test "a signed-in request marks the user seen, at most every five minutes", %{ada: ada} do
    seen = Idejo.Accounts.seen(Repo.reload!(ada))
    assert DateTime.diff(DateTime.utc_now(), seen.last_seen_at) < 5
    assert Idejo.Accounts.seen(seen).last_seen_at == seen.last_seen_at
  end
end

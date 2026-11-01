# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Inactive topics (steward decision, 2026-11-01): a topic nobody follows is shown faded.
# Not async: one test turns the `inactive_topics` setting off.
defmodule IdejoWeb.InactiveTopicsTest do
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Forum
  alias Idejo.Reading
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    starter = user_fixture()

    {:ok, topic} =
      Forum.create_topic(starter, general, %{"title" => "Picnic", "body" => "Saturday?"})

    %{admin: admin, general: general, starter: starter, topic: topic}
  end

  defp inactive?(topic), do: hd(Reading.put_inactive([topic])).inactive

  @tag req: "TP-13"
  test "TP-13 a topic nobody follows is inactive", %{starter: starter, topic: topic} do
    refute inactive?(topic)

    :ok = Reading.unfollow(starter, topic)
    assert inactive?(topic)

    # Tuples, as the Unread page holds them, keep their extra.
    assert [{%{inactive: true}, 3}] = Reading.put_inactive([{topic, 3}])

    :ok = Reading.follow(user_fixture(), topic)
    refute inactive?(topic)
  end

  @tag req: "TP-13"
  test "TP-13 a topic followed by everyone, or followed only by a deleted account", %{
    admin: admin,
    starter: starter,
    topic: topic
  } do
    {:ok, _} = Accounts.delete_user(starter, valid_user_password())
    assert inactive?(topic)

    {:ok, topic} = Forum.set_autofollow(admin, topic, true)
    refute inactive?(topic)
  end

  @tag req: "TP-13"
  test "TP-13 the category page fades inactive topics, unless the setting is off", %{
    conn: conn,
    admin: admin,
    general: general,
    starter: starter,
    topic: topic
  } do
    :ok = Reading.unfollow(starter, topic)
    page = conn |> get(~p"/c/#{general.slug}") |> html_response(200)
    assert page =~ ~r/id="topic-#{topic.id}"[^>]*is-inactive/s
    assert page =~ "topic-inactive"

    {:ok, _} = Settings.update_settings(admin, %{"inactive_topics" => "false"})
    page = conn |> get(~p"/c/#{general.slug}") |> html_response(200)
    refute page =~ "is-inactive"
  end
end

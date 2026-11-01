# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Automessages (steward decision, 2026-11-01): Admin → Automessages and the composer's command.
defmodule IdejoWeb.AutomessagesLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Accounts
  alias Idejo.Forum
  alias Idejo.Messages.Automessages

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture()
    {:ok, topic} = Forum.create_topic(member, general, %{"title" => "Hi", "body" => "Hello"})
    %{admin: admin, member: member, topic: topic}
  end

  defp commands(view) do
    [json] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#composer")
      |> LazyHTML.attribute("data-commands")

    json |> Jason.decode!() |> Enum.map(& &1["label"])
  end

  defp watch(conn, user, topic),
    do:
      live_isolated(log_in_user(conn, user), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

  test "administrators make an automessage with its sender and picture", %{
    conn: conn,
    admin: admin
  } do
    {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/admin/automessages")
    # The defaults (steward decision, 2026-11-01).
    assert html =~ "!tutorial-message"
    username = unique_username("bot")
    name = "faq-#{System.unique_integer([:positive])}"

    lv
    |> file_input("#automessage-form", :picture, [
      %{name: "bot.png", content: File.read!(image_file(:png)), type: "image/png"}
    ])
    |> render_upload("bot.png")

    html =
      lv
      |> form("#automessage-form",
        automessage: %{
          command: "!" <> name,
          body_md: "See /help.",
          sender_username: username,
          everyone: "true",
          cooldown_minutes: "5"
        }
      )
      |> render_submit()

    assert html =~ "Automessage !#{name} saved."

    assert %{sender: sender, everyone: true, cooldown_minutes: 5} =
             Enum.find(Automessages.list(), &(&1.command == name))

    assert sender.username == username and sender.avatar_id
    assert has_element?(lv, "#automessages li", "!#{name}")
    assert has_element?(lv, "#automessages li", "Waits 5 minutes")

    html =
      lv
      |> form("#automessage-form",
        automessage: %{command: "poll", body_md: "x", sender_username: username}
      )
      |> render_submit()

    assert html =~ "is one of the composer&#39;s own commands"
  end

  test "moderators get the commands in the composer and the server posts them", %{
    conn: conn,
    admin: admin,
    member: member,
    topic: topic
  } do
    name = "hello-#{System.unique_integer([:positive])}"

    {:ok, automessage} =
      Automessages.create(admin, %{
        "command" => name,
        "body_md" => "Be kind.",
        "sender_username" => unique_username("bot"),
        "cooldown_minutes" => "3"
      })

    {:ok, view, _html} = watch(conn, member, topic)
    refute "!#{name}" in commands(view)
    refute "!rules" in commands(view)

    moderator = user_with_role_fixture(:moderator)
    {:ok, view, _html} = watch(build_conn(), moderator, topic)
    assert "!#{name}" in commands(view)
    assert "!rules" in commands(view)

    render_hook(view, "automessage", %{"name" => name})
    sender = Accounts.get_user!(automessage.sender_id)
    assert [_, %{author_id: author_id}] = Forum.list_messages(topic)
    assert author_id == sender.id
    assert render(view) =~ "Be kind."
    assert render(view) =~ sender.username

    assert render_hook(view, "automessage", %{"name" => name}) =~
             "It can be used again in 3 minutes."
  end
end

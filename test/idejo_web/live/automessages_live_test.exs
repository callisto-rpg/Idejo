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
    # A server account holds no role, so none shows next to its name (not "Guest").
    assert Idejo.Access.roles_of(sender) == []

    [_, posted] = Forum.list_messages(topic)
    assert has_element?(view, "#message-#{posted.id}-author", sender.username)
    refute has_element?(view, "#message-#{posted.id}-author .author-role")
    refute render(view) =~ "Guest"

    assert render_hook(view, "automessage", %{"name" => name}) =~
             "It can be used again in 3 minutes."
  end

  # Steward decision, 2026-11-02.
  test "an automessage may post a poll, set up with the poll's fields", %{
    conn: conn,
    admin: admin
  } do
    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/automessages")
    refute has_element?(lv, "#automessage-poll")

    lv
    |> form("#automessage-form", automessage: %{command: "lunch", poll_on: "true"})
    |> render_change()

    assert has_element?(lv, "#automessage-poll #automessage-poll-question")
    assert has_element?(lv, "#automessage-poll-colour-1[type=color]")
    problems = IdejoWeb.Accessibility.audit(render(lv), page: false)
    assert problems == [], Enum.join(problems, "\n")
    lv |> element("#automessage-poll-add-option") |> render_click()
    assert has_element?(lv, "#automessage-poll-option-2")

    # The emoji picker for an answer.
    lv |> element("#automessage-poll-emoji-0") |> render_click()
    assert has_element?(lv, ~s(#emoji-picker-body[data-poll-option="0"]))
    render_hook(lv, "poll_emoji", %{"emoji" => "pizza"})
    refute has_element?(lv, "#emoji-picker")

    assert lv
           |> form("#automessage-form",
             automessage: %{
               command: "lunch",
               body_md: "",
               sender_username: "idejo",
               poll_on: "true",
               poll: %{question: "", options: ["A", "B", ""], hours: "1"}
             }
           )
           |> render_submit() =~ "The poll needs a question."

    lv
    |> form("#automessage-form",
      automessage: %{
        command: "lunch",
        body_md: "",
        sender_username: "idejo",
        poll_on: "true",
        poll: %{
          question: "Lunch?",
          options: ["Pizza", "Soup", ""],
          emojis: ["pizza", "", ""],
          hide_results: "true",
          hours: "1"
        }
      }
    )
    |> render_submit()

    assert has_element?(lv, "#automessages li", "Poll")
    automessage = Enum.find(Automessages.list(), &(&1.command == "lunch"))
    assert %{"question" => "Lunch?", "hide_results" => true} = automessage.poll
    assert [%{"emoji" => "pizza"}, %{"text" => "Soup"}] = automessage.poll["options"]

    # Edited, the form shows what is kept.
    lv |> element("#automessage-#{automessage.id} button", "Edit") |> render_click()
    assert lv |> element("#automessage-poll-question") |> render() =~ ~s(value="Lunch?")
    assert lv |> element("#automessage-poll-emoji-0") |> render() =~ ":pizza:"
  end
end

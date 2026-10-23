# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The composer's ! commands (steward decision, 2026-10-23).
defmodule IdejoWeb.ComposerCommandsTest do
  use IdejoWeb.ConnCase, async: true
  use Oban.Testing, repo: Idejo.Repo

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages.{ScheduledMessage, ScheduledWorker}
  alias Idejo.Repo

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    ada = user_fixture(%{display_name: "Ada"})
    {:ok, topic} = Forum.create_topic(ada, general, %{"title" => "Plans", "body" => "Ideas?"})
    [first] = Forum.list_messages(topic)
    member = user_fixture(%{display_name: "Bo"})

    %{
      conn: log_in_user(conn, member),
      admin: admin,
      general: general,
      member: member,
      topic: topic,
      first: first
    }
  end

  defp watch(conn, topic, session \\ %{}),
    do:
      live_isolated(conn, IdejoWeb.TopicLive,
        session: Map.merge(%{"topic_id" => topic.id}, session)
      )

  defp commands(view) do
    [json] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#composer")
      |> LazyHTML.attribute("data-commands")

    json |> Jason.decode!() |> Enum.map(& &1["label"])
  end

  test "the composer offers the commands its author may use", %{
    conn: conn,
    admin: admin,
    general: general,
    topic: topic
  } do
    {:ok, view, _html} = watch(conn, topic)
    assert commands(view) == ["!image", "!new-topic", "!schedule"]

    # Without the start right anywhere (General is the only category) there is no !new-topic.
    {:ok, _} =
      Access.set_permission(admin, Access.built_in_role!(:member), general, :start, :deny)

    {:ok, view, _html} = watch(conn, topic)
    assert commands(view) == ["!image", "!schedule"]
  end

  @tag req: "TP-09"
  test "TP-09 !new-topic sends, then starts a topic from the message with its text", %{
    conn: conn,
    topic: topic
  } do
    {:ok, view, _html} = watch(conn, topic)

    assert {:error, {:redirect, %{to: to}}} =
             render_hook(view, "commit", %{
               "body" => "Snacks deserve their own thread",
               "break" => false,
               "then" => "new_topic"
             })

    [_, sent] = Forum.list_messages(topic)
    assert sent.body_md == "Snacks deserve their own thread."
    assert to == "/m/#{sent.id}/new-topic?from=#{sent.id}"

    {:ok, new_topic, _html} = live(conn, to)
    assert new_topic |> element("#forked-from") |> has_element?()
    assert render(new_topic) =~ "Snacks deserve their own thread."

    # Nothing new to send: the open message is the one.
    {:ok, view, _html} = watch(conn, topic)
    assert {:error, {:redirect, %{to: again}}} = render_hook(view, "new_topic", %{})
    assert again == to
  end

  @tag req: "TP-09"
  test "TP-09 !new-topic in a reply starts from the message replied to", %{
    conn: conn,
    topic: topic,
    first: first
  } do
    {:ok, view, _html} = watch(conn, topic, %{"reply_to_id" => first.id})

    assert {:error, {:redirect, %{to: to}}} =
             render_hook(view, "commit", %{
               "body" => "Agreed",
               "break" => false,
               "then" => "new_topic"
             })

    [_, sent] = Forum.list_messages(topic)
    assert to == "/m/#{first.id}/new-topic?from=#{sent.id}"

    # Only one's own message fills the new topic: Ada's stays out of Bo's form.
    {:ok, other, _html} = live(conn, "/m/#{first.id}/new-topic?from=#{first.id}")
    refute other |> element("textarea") |> render() =~ "Ideas?"
  end

  test "!new-topic with nothing sent asks for the message first", %{conn: conn, topic: topic} do
    {:ok, view, _html} = watch(conn, topic)
    assert render_hook(view, "new_topic", %{}) =~ "Write your message first"
  end

  test "!schedule asks for hours, then lists the message for its author, who may cancel it", %{
    conn: conn,
    member: member,
    topic: topic
  } do
    {:ok, view, _html} = watch(conn, topic)

    # Only text not sent yet.
    assert render_hook(view, "open_schedule", %{"body" => " "}) =~
             "Only text not sent yet can be scheduled"

    refute has_element?(view, "#schedule-dialog")

    render_hook(view, "open_schedule", %{"body" => "Reminder: bring chairs"})
    assert has_element?(view, "#schedule-dialog", "Reminder: bring chairs")

    assert view |> form("#schedule-form", %{hours: "200"}) |> render_submit() =~
             "Enter a number of hours above 0, at most 168."

    view |> form("#schedule-form", %{hours: "1.5"}) |> render_submit()
    assert_push_event(view, "composer_scheduled", %{body: "Reminder: bring chairs"})
    refute has_element?(view, "#schedule-dialog")

    [scheduled] = Repo.all(ScheduledMessage)
    assert scheduled.author_id == member.id
    assert has_element?(view, "#scheduled-#{scheduled.id}", "Reminder: bring chairs")

    # Others see nothing of it.
    {:ok, other, _html} = watch(log_in_user(build_conn(), user_fixture()), topic)
    refute has_element?(other, "#scheduled-messages")

    view |> element("#scheduled-#{scheduled.id} button", "Cancel") |> render_click()
    refute has_element?(view, "#scheduled-messages")
    assert Repo.all(ScheduledMessage) == []
  end

  test "a scheduled message, once posted, reads “scheduled message”", %{
    conn: conn,
    topic: topic
  } do
    {:ok, view, _html} = watch(conn, topic)
    render_hook(view, "open_schedule", %{"body" => "Good morning"})
    view |> form("#schedule-form", %{hours: "8"}) |> render_submit()
    [scheduled] = Repo.all(ScheduledMessage)

    assert perform_job(ScheduledWorker, %{id: scheduled.id}) == :ok

    [_, posted] = Forum.list_messages(topic)
    assert has_element?(view, "#message-#{posted.id}-scheduled", "scheduled message")
    refute has_element?(view, "#scheduled-messages")
  end
end

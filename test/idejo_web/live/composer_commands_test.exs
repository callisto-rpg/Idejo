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
  alias Idejo.Messages
  alias Idejo.Messages.{Polls, PollWorker, ScheduledMessage, ScheduledWorker}
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
    assert commands(view) == ["!image", "!new-topic", "!poll", "!schedule", "!spoiler"]

    # Without the start right anywhere (General is the only category) there is no !new-topic.
    {:ok, _} =
      Access.set_permission(admin, Access.built_in_role!(:member), general, :start, :deny)

    {:ok, view, _html} = watch(conn, topic)
    assert commands(view) == ["!image", "!poll", "!schedule", "!spoiler"]
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

  test "!poll sends, then adds a poll under the message, where posters vote", %{
    conn: conn,
    member: member,
    topic: topic
  } do
    {:ok, view, _html} = watch(conn, topic)

    render_hook(view, "commit", %{
      "body" => "Where shall we meet",
      "break" => false,
      "then" => "poll"
    })

    assert has_element?(view, "#poll-dialog")
    [_, sent] = Forum.list_messages(topic)

    # Two answers to start with; Add an answer for more, keeping what was typed.
    view |> form("#poll-form", poll: %{question: "Where?"}) |> render_change()
    view |> element("#poll-add-option") |> render_click()
    assert has_element?(view, "#poll-option-2")
    assert view |> element("#poll-question") |> render() =~ ~s(value="Where?")

    assert view
           |> form("#poll-form",
             poll: %{question: "Where?", options: ["Park", "", ""], hours: "24"}
           )
           |> render_submit() =~ "Give at least two answers."

    view
    |> form("#poll-form",
      poll: %{question: "Where?", options: ["Park", "Café", ""], multiple: "false", hours: "24"}
    )
    |> render_submit()

    refute has_element?(view, "#poll-dialog")
    # Under the author's open message, in the composer's place.
    assert has_element?(view, "#message-#{sent.id} #poll-#{sent.id}", "Where?")

    # Another poster votes; they see the counts only then.
    other = user_fixture(%{display_name: "Cy"})
    {:ok, theirs, _html} = watch(log_in_user(build_conn(), other), topic)
    assert has_element?(theirs, "#poll-#{sent.id}", "Results show once you vote.")
    refute has_element?(theirs, "#poll-#{sent.id} .poll-count")

    %{options: [park, _cafe]} = Polls.summary(sent.id)

    theirs
    |> form("#poll-#{sent.id}", %{"options" => [park.id]})
    |> render_submit()

    assert has_element?(theirs, "#poll-#{sent.id} .poll-count", "1 vote (100%)")
    assert has_element?(theirs, "#poll-#{sent.id} button", "Change vote")
    # The author sees the counts as they come.
    assert has_element?(view, "#poll-#{sent.id} .poll-count", "1 vote (100%)")

    # One poll per message.
    assert render_hook(view, "open_poll", %{}) =~ "This message has a poll already."
    assert member.id == sent.author_id
  end

  test "!poll with nothing written posts the poll as a message of its own", %{
    conn: conn,
    member: member,
    topic: topic
  } do
    {:ok, view, _html} = watch(conn, topic)

    render_hook(view, "open_poll", %{})
    assert has_element?(view, "#poll-dialog")

    # Nothing is posted while the poll is incomplete.
    assert view
           |> form("#poll-form", poll: %{question: "", options: ["Park", "Café"], hours: "24"})
           |> render_submit() =~ "Write the question."

    assert [_opening] = Forum.list_messages(topic)

    view
    |> form("#poll-form",
      poll: %{question: "Where?", options: ["Park", "Café"], multiple: "false", hours: "24"}
    )
    |> render_submit()

    refute has_element?(view, "#poll-dialog")
    [_, posted] = Forum.list_messages(topic)
    assert posted.author_id == member.id
    assert posted.body_md == "Where?"
    assert posted.closed_at
    assert %{question: "Where?"} = Polls.summary(posted.id)

    # The question shows once, as the poll's.
    assert has_element?(view, "#message-#{posted.id} #poll-#{posted.id}", "Where?")
    refute has_element?(view, "#message-#{posted.id}-body")
  end

  test "a poll closes at its time and shows everyone its counts", %{conn: conn, topic: topic} do
    {:ok, view, _html} = watch(conn, topic)
    render_hook(view, "commit", %{"body" => "Pick one", "break" => false})
    [_, sent] = Forum.list_messages(topic)
    member = Repo.preload(sent, :author).author

    {:ok, %{id: poll_id}} =
      Polls.create(member, sent, %{
        "question" => "Tea?",
        "options" => ["Yes", "No"],
        "hours" => "1"
      })

    assert_enqueued(worker: PollWorker, args: %{id: poll_id})
    Repo.update_all(Messages.Poll, set: [closes_at: DateTime.add(DateTime.utc_now(), -1)])

    {:ok, reader, _html} = watch(build_conn(), topic)
    assert perform_job(PollWorker, %{id: poll_id}) == :ok
    assert has_element?(view, "#poll-#{sent.id} .poll-closed", "Closed")
    assert has_element?(reader, "#poll-#{sent.id} .poll-count", "0 votes (0%)")
    refute has_element?(reader, "#poll-#{sent.id} button")
  end

  test "!spoiler hides the message behind Reveal spoiler, and again shows it", %{
    conn: conn,
    topic: topic
  } do
    {:ok, view, _html} = watch(conn, topic)
    assert render_hook(view, "spoiler", %{}) =~ "Write your message first, then choose !spoiler."

    assert render_hook(view, "commit", %{
             "body" => "The butler did it",
             "break" => false,
             "then" => "spoiler"
           }) =~ "Your message is hidden as a spoiler."

    [_, sent] = Forum.list_messages(topic)
    assert sent.spoiler

    {:ok, reader, _html} = watch(log_in_user(build_conn(), user_fixture()), topic)
    assert has_element?(reader, "#message-#{sent.id}-reveal", "Reveal spoiler")
    # Out of reach of the keyboard and screen readers until revealed.
    assert has_element?(reader, "#message-#{sent.id}-hidden[inert]")

    reader |> element("#message-#{sent.id}-reveal") |> render_click()
    refute has_element?(reader, "#message-#{sent.id}-reveal")
    refute has_element?(reader, "#message-#{sent.id}-hidden[inert]")

    # Quotes give nothing away.
    assert Forum.excerpt(Repo.reload!(sent)) == "(spoiler)"

    # Without scripts (the page's first render) there is no inert: the text reads as usual.
    html = build_conn() |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)
    assert html =~ "The butler did it"
    refute html |> LazyHTML.from_document() |> LazyHTML.query("[inert]") |> Enum.any?()

    assert render_hook(view, "spoiler", %{}) =~ "Your message is no longer a spoiler."
    refute Repo.reload!(sent).spoiler
    refute has_element?(reader, "#message-#{sent.id}-reveal")
  end
end

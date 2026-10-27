# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.LiveNotificationsTest do
  @moduledoc """
  Live notifications (steward decision, 2026-10-23): each notification is announced on the
  user's channel once its message is committed, `IdejoWeb.NotifierLive` hands it to the
  browser as a bubble, and `/sidebar` serves the sidebar for the browser to bring up to date.
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Notifications
  alias Idejo.Reactions
  alias Idejo.Reading
  alias Idejo.Repo

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    ada = user_fixture(%{username: unique_username("ada"), display_name: "Ada"})
    bo = user_fixture(%{username: unique_username("bo"), display_name: "Bo"})
    {:ok, topic} = Forum.create_topic(ada, general, %{"title" => "Plans", "body" => "Tonight?"})
    [first] = Forum.list_messages(topic)

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, ada: ada, bo: bo, topic: topic, first: first}
  end

  defp listen(user), do: :ok = Notifications.subscribe(user)

  @tag req: "NO-01"
  test "NO-01 each notification is announced live, with its kind, after the message is written",
       %{admin: admin, ada: ada, bo: bo, topic: topic, first: first} do
    {:ok, crew} =
      Access.create_role(admin, %{"name" => unique_role_name("Crew"), "mentionable" => "true"})

    cy = user_fixture()
    :ok = Access.grant_role(cy, crew)
    dee = user_fixture()
    :ok = Reading.follow(dee, topic)
    for user <- [ada, bo, cy, dee], do: listen(user)

    {:ok, message} =
      Forum.post_message(bo, topic, %{
        "body" => "Yes @#{ada.username}, +#{Access.role_slug(crew)}",
        "reply_to_id" => first.id
      })

    assert_receive {:notification, %{kind: "mention"} = live}
    assert live.message_id == message.id
    assert live.topic_id == topic.id
    assert {live.author_name, live.topic_title} == {"Bo", "Plans"}
    assert live.excerpt =~ "Yes"
    assert_receive {:notification, %{kind: "role_mention"}}
    assert_receive {:notification, %{kind: "follow"}}
    # One each, and nothing for the author.
    refute_receive {:notification, _}, 50
  end

  @tag req: "NO-02"
  test "NO-02 a growing message is announced when it opens, then only for someone newly mentioned",
       %{ada: ada, bo: bo, topic: topic} do
    :ok = Reading.follow(bo, topic)
    listen(bo)

    {:ok, _} = Messages.commit(ada, topic, "First line")
    assert_receive {:notification, %{kind: "follow"}}

    {:ok, _} = Messages.commit(ada, topic, "First line. More")
    refute_receive {:notification, _}, 50

    {:ok, _} = Messages.commit(ada, topic, "First line. More, @#{bo.username}")
    assert_receive {:notification, %{kind: "mention"}}
  end

  @tag req: "NO-01"
  test "NO-01 a new topic announces the people its first message mentions", %{
    general: general,
    ada: ada,
    bo: bo
  } do
    listen(bo)

    {:ok, _} =
      Forum.create_topic(ada, general, %{"title" => "Help", "body" => "@#{bo.username}?"})

    assert_receive {:notification, %{kind: "mention", topic_title: "Help"}}
  end

  @tag req: "NO-01"
  test "NO-01 a notification written by a transaction that failed is never announced", %{
    ada: ada,
    bo: bo,
    topic: topic
  } do
    listen(bo)
    {:ok, quiet} = Forum.post_message(ada, topic, %{"body" => "Nothing for Bo"})

    {:error, :boom} =
      Repo.transact(fn ->
        {:ok, 1} = Notifications.notify_new(%{quiet | body_md: "@#{bo.username}"}, topic)
        {:error, :boom}
      end)

    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "Still nothing for Bo"})
    refute_receive {:notification, _}, 50
  end

  @tag req: "TP-17"
  test "TP-17 a reaction is announced to the author only, when added", %{
    ada: ada,
    bo: bo,
    first: first
  } do
    listen(ada)
    listen(bo)

    {:ok, _} = Reactions.toggle(bo, first, "joy")
    assert_receive {:notification, %{kind: "reaction", author_name: "Bo", emoji: emoji}}
    assert emoji.alt == "😂"
    assert emoji.src =~ "/emoji/1f602.svg"

    # Taking it back, or reacting to one's own message, announces nothing.
    {:ok, _} = Reactions.toggle(bo, first, "joy")
    {:ok, _} = Reactions.toggle(ada, first, "heart")
    refute_receive {:notification, _}, 50
  end

  test "the notifier hands each notification to the browser as a bubble", %{
    ada: ada,
    bo: bo,
    topic: topic
  } do
    {:ok, lv, html} = live_isolated(log_in_user(build_conn(), ada), IdejoWeb.NotifierLive)
    assert html =~ ~s(phx-hook="Notifier")
    assert html =~ ~s(id="bubbles")
    assert html =~ ~s(aria-live="polite")
    assert html =~ ~s(data-sidebar="/sidebar")

    {:ok, message} = Forum.post_message(bo, topic, %{"body" => "Ask @#{ada.username}"})

    assert_push_event(lv, "notification", %{
      kind: "mention",
      text: "Bo mentioned you in “Plans”",
      href: href,
      topic_id: topic_id
    })

    assert href == "/m/#{message.id}?unread"
    assert topic_id == topic.id
  end

  test "every signed-in page carries the notifier; visitors' pages do not", %{ada: ada} do
    assert log_in_user(build_conn(), ada) |> get(~p"/") |> html_response(200) =~
             ~s(id="notifier")

    refute build_conn() |> get(~p"/") |> html_response(200) =~ ~s(id="notifier")
  end

  test "/sidebar serves the sidebar alone, with the followed topics' dots", %{
    ada: ada,
    bo: bo,
    general: general,
    topic: topic
  } do
    :ok = Reading.follow(bo, topic)
    {:ok, _} = Forum.post_message(ada, topic, %{"body" => "Ping @#{bo.username}"})

    conn = log_in_user(build_conn(), bo) |> get(~p"/sidebar?category=#{general.id}")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    doc = conn |> html_response(200) |> LazyHTML.from_fragment()

    assert doc
           |> LazyHTML.query("aside#sidebar .sidebar-topic .sidebar-dot.is-mention")
           |> Enum.count() == 1

    assert doc |> LazyHTML.query(~s(a.is-current[aria-current="page"])) |> Enum.count() == 1
    assert redirected_to(get(build_conn(), ~p"/sidebar")) == ~p"/users/sign-in"
  end

  test "the sidebar is fetched every 5 s for 20 s, then every 30 s, past 5 min every 10 min" do
    js = File.read!("assets/js/notifier.js")
    assert js =~ "age < 20000 ? 5000 : age < 300000 ? 30000 : 600000"
    assert js =~ "phx:page-loading-stop"
  end

  test "bubbles are see-through, blurred, lined and glowing" do
    css = File.read!("assets/css/app.css")
    [bubble] = Regex.run(~r/^\.bubble \{.*?^\}/ms, css)
    assert bubble =~ ~r/var\(--color-base-100\)\) 75%,\s*transparent/
    assert bubble =~ "backdrop-filter: blur(3px)"
    assert bubble =~ "border: 1px solid var(--bubble)"
    assert bubble =~ "0 0 22px -6px"

    for kind <- ~w(role-mention reply mention reaction), do: assert(bubble =~ "&.is-#{kind} {")
  end
end

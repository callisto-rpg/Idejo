# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TopicWindowTest do
  @moduledoc """
  Long topics, a window at a time (steward decision, 2026-11-01), with the "Performance"
  setting on Light: 5 messages before the one a reader lands on, 15 after, 20 more at each
  scroll, at most 100 at once, pages of 25 without JavaScript.
  """
  # Sets a server-wide setting.
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Forum.TopicWindow
  alias Idejo.Reading
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, _} = Settings.update_settings(admin, %{"performance" => "light"})
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture(%{display_name: "Ada"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: admin, general: general, author: author}
  end

  # A topic of `n` messages, "Message 1" (the opening one) to "Message n".
  defp long_topic(%{general: general, author: author}, n) do
    {:ok, topic} =
      Forum.create_topic(author, general, %{"title" => "Long", "body" => "Message 1"})

    for i <- 2..n//1, do: say(topic, author, "Message #{i}")
    {topic, Forum.list_messages(topic)}
  end

  defp say(topic, author, body) do
    {:ok, message} = Forum.post_message(author, topic, %{"body" => body})
    message
  end

  # The numbers of the messages shown, in order, from "Message n".
  defp numbers(html, selector \\ "li[id^='message-']") do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector <> " .message-body")
    |> Enum.map(&LazyHTML.text/1)
    |> Enum.map(fn text -> text |> String.trim() |> String.trim_leading("Message ") end)
    |> Enum.map(&(&1 |> String.trim_trailing(".") |> String.to_integer()))
  end

  defp at(messages, n), do: Enum.at(messages, n - 1)

  defp open(conn, topic, window \\ %{}),
    do:
      live_isolated(conn, IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id, "window" => window}
      )

  @tag req: "AD-02"
  test "AD-02 Performance: Light loads half as many messages as Normal, Heavy three times", %{
    admin: admin
  } do
    assert TopicWindow.sizes("normal") == %{before: 10, after: 30, step: 40, cap: 200, page: 50}
    assert TopicWindow.sizes("light") == %{before: 5, after: 15, step: 20, cap: 100, page: 25}
    assert TopicWindow.sizes("heavy") == %{before: 30, after: 90, step: 120, cap: 600, page: 150}

    {:ok, lv, html} = live(log_in_user(build_conn(), admin), ~p"/admin")
    assert html =~ "Performance"
    assert html =~ "Light (for smaller servers)"
    assert html =~ "Normal (recommended)"
    assert html =~ "Heavy (for more powerful servers)"

    lv |> form("#settings-form", settings: %{performance: "heavy"}) |> render_submit()
    assert Settings.get(:performance) == "heavy"
    assert TopicWindow.sizes() == TopicWindow.sizes("heavy")
  end

  @tag req: "TP-06"
  test "TP-06 a permalink deep in a long topic leads to its message, with those around it",
       context do
    {topic, messages} = long_topic(context, 60)
    target = at(messages, 30)

    path = redirected_to(get(build_conn(), ~p"/m/#{target.id}"), 302)
    assert path == "/t/#{topic.id}/#{topic.slug}?around=#{target.id}#message-#{target.id}"

    html = build_conn() |> get(path) |> html_response(200)
    # The opening message on top, then 5 before, the message and 15 after.
    assert numbers(html, "#opening-message li") == [1]
    assert numbers(html, "#messages > li") == Enum.to_list(25..45)
    # Without JavaScript, links to the pages that hold the rest (pages of 25).
    assert html =~ ~s(href="/t/#{topic.id}/#{topic.slug}?page=1")
    assert html =~ ~s(href="/t/#{topic.id}/#{topic.slug}?page=2")
    assert html =~ "23 earlier messages"
    assert html =~ "15 later messages"
  end

  @tag req: "TP-07"
  test "TP-07 back in a long topic, it opens at the first unread message", context do
    {topic, _} = long_topic(context, 20)
    reader = user_fixture()
    :ok = Reading.mark_read(reader, topic)
    for i <- 21..60, do: say(topic, context.author, "Message #{i}")

    html = log_in_user(build_conn(), reader) |> get(~p"/t/#{topic.id}/#{topic.slug}")
    html = html_response(html, 200)

    assert numbers(html, "#messages > li") == Enum.to_list(16..36)
    assert html =~ "40 unread messages"
  end

  @tag req: "AX-04"
  test "AX-04 without JavaScript, a long topic reads page by page from its end", context do
    {topic, _} = long_topic(context, 60)

    # Nothing unread: the end, the opening message on top.
    html = build_conn() |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)
    assert numbers(html, "#opening-message li") == [1]
    assert numbers(html, "#messages > li") == Enum.to_list(41..60)
    assert html =~ ~s(href="/t/#{topic.id}/#{topic.slug}?page=2")
    refute html =~ "later message"
    assert IdejoWeb.Accessibility.audit(html) == []

    # Page 2 of 25: messages 26 to 50, a link to each neighbour.
    html = build_conn() |> get(~p"/t/#{topic.id}/#{topic.slug}?page=2") |> html_response(200)
    assert numbers(html, "#messages > li") == Enum.to_list(26..50)
    assert html =~ ~s(href="/t/#{topic.id}/#{topic.slug}?page=1")
    assert html =~ ~s(href="/t/#{topic.id}/#{topic.slug}?page=3")
    assert IdejoWeb.Accessibility.audit(html) == []

    # A page past the end shows the last one.
    html = build_conn() |> get(~p"/t/#{topic.id}/#{topic.slug}?page=9") |> html_response(200)
    assert numbers(html, "#messages > li") == Enum.to_list(51..60)
  end

  @tag req: "SE-04"
  test "SE-04 the pages of a long topic name their own canonical address", context do
    {topic, messages} = long_topic(context, 30)
    url = "http://localhost:4000/t/#{topic.id}/#{topic.slug}"

    canonical = fn topic, query ->
      html = build_conn() |> get("/t/#{topic.id}/#{topic.slug}" <> query) |> html_response(200)
      [_, href] = Regex.run(~r/<link rel="canonical" href="([^"]+)">/, html)
      href
    end

    # Pages of 25. The first is a page of its own: the topic's address opens at its end.
    assert canonical.(topic, "?page=1") == url <> "?page=1"
    assert canonical.(topic, "?page=2") == url <> "?page=2"
    # Past the end, the last page; not a page, the topic's address.
    assert canonical.(topic, "?page=9") == url <> "?page=2"
    assert canonical.(topic, "?page=abc") == url
    assert canonical.(topic, "?around=#{at(messages, 3).id}") == url
    assert canonical.(topic, "") == url

    # A topic of one page has one address.
    {short, _} = long_topic(context, 10)
    assert canonical.(short, "?page=1") == "http://localhost:4000/t/#{short.id}/#{short.slug}"
  end

  # Found by the load test (200 viewers, 30 writing): a message posted between the view's
  # count of the topic and its load of the end made a topic just short of a window load
  # whole, opening message included, while the count said it did not start at the
  # beginning, so the opening message was pinned on top as well: the same key twice, and the
  # page crashed.
  @tag req: "TP-04"
  test "TP-04 a message posted while the view loads the end never shows a message twice",
       context do
    {topic, _messages} = long_topic(context, 19)
    test_pid = self()
    handler = "window-race-#{System.unique_integer()}"

    # Right after the count of the topic's messages, someone posts.
    :telemetry.attach(
      handler,
      [:idejo, :repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if query =~ ~s{SELECT count(*) FROM "messages"} and
             :persistent_term.get(handler, nil) == nil do
          :persistent_term.put(handler, true)
          send(test_pid, :posted)
          say(topic, context.author, "Message 20")
        end
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler)
      :persistent_term.erase(handler)
    end)

    {:ok, lv, html} = open(build_conn(), topic)
    assert_received :posted
    assert numbers(html) == Enum.to_list(1..20)
    assert numbers(render(lv)) == Enum.to_list(1..20)
    refute has_element?(lv, "#opening-message")
    refute has_element?(lv, "#earlier-messages")
  end

  @tag req: "TP-04"
  test "TP-04 scrolling to an edge loads the messages before or after, at most 100 at once",
       context do
    {topic, messages} = long_topic(context, 130)
    shown = fn lv -> numbers(render(lv), "#messages > li") end

    {:ok, lv, _html} = open(build_conn(), topic, %{"around" => at(messages, 30).id})
    assert shown.(lv) == Enum.to_list(25..45)

    # The button between the windows, or LiveView's viewport event at the edge.
    lv |> element("#earlier-messages button") |> render_click()
    assert shown.(lv) == Enum.to_list(5..45)

    render_hook(lv, "load_later", %{"id" => "message-#{at(messages, 45).id}"})
    assert shown.(lv) == Enum.to_list(5..65)

    # Past 100, loading later drops the earliest; the opening message stays on top.
    for _ <- 1..4, do: render_hook(lv, "load_later", %{})
    assert shown.(lv) == Enum.to_list(31..130)
    assert numbers(render(lv), "#opening-message li") == [1]
    assert IdejoWeb.Accessibility.audit(render(lv), page: false) == []

    # Loading earlier drops the latest past 100: the window leaves the end.
    for _ <- 1..2, do: render_hook(lv, "load_earlier", %{})
    assert shown.(lv) == Enum.to_list(1..101)
    assert has_element?(lv, "#later-messages", "29 later messages")
    refute has_element?(lv, "#earlier-messages")

    # Who may write keeps the end, where the composer holds what they have not sent yet.
    member = log_in_user(build_conn(), user_fixture())
    {:ok, lv, _html} = open(member, topic)
    assert shown.(lv) == Enum.to_list(111..130)
    for _ <- 1..5, do: render_hook(lv, "load_earlier", %{})
    assert shown.(lv) == Enum.to_list(11..130)
    assert has_element?(lv, "#composer")
  end

  @tag req: "TP-04"
  test "TP-04 a viewer who loses the view right in a long topic stops seeing it", context do
    {topic, messages} = long_topic(context, 60)
    {:ok, lv, _html} = open(build_conn(), topic, %{"around" => at(messages, 30).id})
    assert has_element?(lv, "#earlier-messages")
    assert has_element?(lv, "#later-messages")

    guest = Idejo.Access.built_in_role!(:guest)
    {:ok, _} = Idejo.Access.set_permission(context.admin, guest, context.general, :view, :deny)

    assert has_element?(lv, "#topic-gone", "You can no longer view this topic.")
    refute has_element?(lv, "#earlier-messages")
    refute has_element?(lv, "#later-messages")
    assert numbers(render(lv)) == []
  end

  @tag req: "TP-04"
  test "TP-04 a new message shows at the end; further up, a button counts it", context do
    {topic, messages} = long_topic(context, 60)
    {:ok, at_end, _html} = open(build_conn(), topic)
    {:ok, up, _html} = open(build_conn(), topic, %{"around" => at(messages, 10).id})

    fresh = say(topic, context.author, "Message 61")

    assert has_element?(at_end, "#message-#{fresh.id}")
    refute has_element?(at_end, "#new-messages")

    refute has_element?(up, "#message-#{fresh.id}")
    assert has_element?(up, "#new-messages", "1 new message")

    # An earlier message out of the window changing shows nowhere.
    {:ok, _} = Forum.post_message(context.author, topic, %{"body" => "Message 62"})
    assert has_element?(up, "#new-messages", "2 new messages")

    up |> element("#new-messages") |> render_click()
    assert has_element?(up, "#message-#{fresh.id}")
    refute has_element?(up, "#new-messages")
  end

  @tag req: "GM-02"
  test "GM-02 the composer is at the end; further up, a button leads there", context do
    {topic, messages} = long_topic(context, 60)
    member = log_in_user(build_conn(), user_fixture())

    {:ok, lv, _html} = open(member, topic, %{"around" => at(messages, 10).id})
    refute has_element?(lv, "#composer")
    assert has_element?(lv, "#jump-to-composer button", "Jump to the end to write")

    lv |> element("#jump-to-composer button") |> render_click()
    assert has_element?(lv, "#composer")
    assert numbers(render(lv), "#messages > li") |> List.last() == 60
    assert_push_event(lv, "composer_focus", %{})

    # Reply from further up goes to the end too, the quote over the composer.
    {:ok, lv, _html} = open(member, topic, %{"around" => at(messages, 10).id})
    lv |> element("#message-#{at(messages, 10).id}-reply") |> render_click()
    assert has_element?(lv, "#composer")
    assert render(lv) =~ "Message 10"
  end

  # The composer is the author's open message (GM-02): never shown without it, or the next
  # Enter would replace the message's text with the composer's.
  @tag req: "GM-02"
  test "GM-02 the composer never shows without the author's open message loaded", context do
    {topic, _} = long_topic(context, 10)
    writer = user_fixture()
    {:ok, open} = Idejo.Messages.commit(writer, topic, "Still writing this")
    for i <- 12..40, do: say(topic, context.author, "Message #{i}")

    # The last page (31 to 40) does not hold the open message.
    {:ok, lv, _html} = open(log_in_user(build_conn(), writer), topic, %{"page" => "2"})
    refute has_element?(lv, "#composer")
    assert has_element?(lv, "#jump-to-composer button")

    # The end does, with the composer in it.
    lv |> element("#jump-to-composer button") |> render_click()
    assert has_element?(lv, "#composer")
    assert has_element?(lv, "li#message-#{open.id} #composer")
  end

  @tag req: "TP-06"
  test "TP-06 the navigator's links load the window around a message not on the page",
       context do
    {topic, messages} = long_topic(context, 60)
    {:ok, lv, _html} = open(build_conn(), topic)
    refute has_element?(lv, "#message-#{at(messages, 20).id}")

    render_hook(lv, "jump", %{"id" => at(messages, 20).id})
    assert numbers(render(lv), "#messages > li") == Enum.to_list(15..35)
    assert_push_event(lv, "scroll_to", %{id: id})
    assert id == "message-#{at(messages, 20).id}"

    # The last message: the end again.
    render_hook(lv, "jump", %{"id" => at(messages, 60).id})
    assert numbers(render(lv), "#messages > li") |> List.last() == 60
  end
end

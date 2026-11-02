# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Forward (steward decision, 2026-11-02): a message sent on to another topic, carried by a
# new message there; its text only for readers who may read it, unless the forwarder wrote it.
defmodule IdejoWeb.ForwardTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Conversations
  alias Idejo.Forum
  alias Idejo.Messages
  alias IdejoWeb.Accessibility

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff"})
    # Members may not view Staff; moderators may (allow wins, RP-06).
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), staff, :view, :deny)

    ada = user_fixture(%{display_name: "Ada"})
    mod = user_with_role_fixture(:moderator, %{display_name: "Mo"})
    bea = user_fixture(%{display_name: "Bea"})

    {:ok, source} = Forum.create_topic(ada, general, %{"title" => "Garden", "body" => "Roses"})
    {:ok, tip} = Forum.post_message(ada, source, %{"body" => "Water them **at dawn**."})
    {:ok, target} = Forum.create_topic(bea, general, %{"title" => "Tips", "body" => "Share"})
    {:ok, secret} = Forum.create_topic(mod, staff, %{"title" => "Staff room", "body" => "Hi"})

    %{
      ada: ada,
      mod: mod,
      bea: bea,
      source: source,
      tip: tip,
      target: target,
      secret: secret
    }
  end

  defp watch(user, topic, session \\ %{}) do
    {:ok, view, _html} =
      live_isolated(log_in_user(build_conn(), user), IdejoWeb.TopicLive,
        session: Map.merge(%{"topic_id" => topic.id}, session)
      )

    view
  end

  defp audit(view) do
    problems = Accessibility.audit(render(view), page: false)
    assert problems == [], Enum.join(problems, "\n")
  end

  test "Forward is on others' messages and one's own once committed; its card lists topics",
       %{ada: ada, bea: bea, source: source, tip: tip, target: target} do
    view = watch(bea, source)
    assert has_element?(view, "#message-#{tip.id}-forward-action", "Forward")

    # One's own open message is still being written; once closed, it may go.
    {:ok, open} = Messages.commit(bea, source, "Still writing")
    view = watch(bea, source)
    refute has_element?(view, "#message-#{open.id}-forward-action")
    assert has_element?(watch(ada, source), "#message-#{tip.id}-forward-action")

    view |> element("#message-#{tip.id}-forward-action") |> render_click()
    assert has_element?(view, "#forward-dialog #forward-dialog-title", "Forward message")
    # Topics one may write in, this one left out, the ones read last first.
    assert has_element?(
             view,
             ~s(#forward-targets a[href="/t/#{target.id}/#{target.slug}?forward=#{tip.id}#composer"]),
             "Tips"
           )

    refute has_element?(view, "#forward-targets a", "Garden")
    audit(view)

    view |> form("#forward-search", %{q: "nothing like it"}) |> render_change()
    assert has_element?(view, "#forward-none")
    view |> form("#forward-search", %{q: "tip"}) |> render_change()
    assert has_element?(view, "#forward-targets a", "Tips")

    # A private conversation: named after the other person, and found by their name.
    {:ok, chat} = Conversations.start(bea, ada)
    view |> form("#forward-search", %{q: "ada"}) |> render_change()

    assert has_element?(
             view,
             ~s(#forward-targets a[href="/p/#{chat.id}?forward=#{tip.id}#composer"]),
             "Ada"
           )

    render_click(view, "close_forward", %{})
    refute has_element?(view, "#forward-dialog")
  end

  test "the topic opens with the message in the composer; sent, it carries it whole",
       %{bea: bea, mod: mod, tip: tip, target: target} do
    view = watch(bea, target, %{"forward_id" => tip.id})
    assert has_element?(view, "#forwarding", "Ada message forwarded from")
    assert has_element?(view, ~s(#forwarding a[href="/m/#{tip.id}"]), "Garden")
    assert has_element?(view, "#forwarding-quote-body strong", "at dawn")
    refute has_element?(view, "#forwarding-quote-show-full")
    audit(view)

    render_hook(view, "commit", %{"body" => "Worth knowing", "break" => false})
    [_, sent] = Forum.list_messages(target)
    assert sent.forwarded_from_id == tip.id
    # Still in the author's open message, now without Cancel forward.
    assert has_element?(view, "#forwarding", "at dawn")
    refute has_element?(view, "#forwarding button", "Cancel forward")

    # Every reader who may read the original sees it, with its topic.
    reader = watch(mod, target)
    assert has_element?(reader, "#message-#{sent.id}-forward", "Ada message forwarded from")
    assert has_element?(reader, "#message-#{sent.id}-forwarded-body strong", "at dawn")
  end

  test "a long message is cut, with Show full message",
       %{ada: ada, bea: bea, source: source, target: target} do
    long = Enum.map_join(1..12, "\n\n", &"Paragraph #{&1}.")
    {:ok, message} = Forum.post_message(ada, source, %{"body" => long})
    view = watch(bea, target, %{"forward_id" => message.id})
    assert has_element?(view, "#forwarding-quote-body.is-clamped", "Paragraph 12.")
    assert has_element?(view, "#forwarding-quote-show-full", "Show full message")

    # Cancel forward: a plain new message again.
    render_click(view, "cancel_forward", %{})
    refute has_element?(view, "#forwarding")
  end

  test "readers who may not view the original see only that it was forwarded",
       %{ada: ada, bea: bea, mod: mod, secret: secret, target: target} do
    {:ok, note} = Forum.post_message(ada, secret, %{"body" => "Hidden plan"})
    # Ada may not view Staff either: she cannot forward it.
    assert {:ok, mine} = Messages.commit(ada, target, "Look", forwarded_from_id: note.id)
    assert mine.forwarded_from_id == nil

    {:ok, sent} = Messages.commit(mod, target, "See this", forwarded_from_id: note.id)
    assert sent.forwarded_from_id == note.id

    view = watch(bea, target)

    assert has_element?(
             view,
             "#message-#{sent.id}-forward",
             "A message forwarded from a topic you cannot view"
           )

    refute render(view) =~ "Hidden plan"
    refute render(view) =~ "Staff room"
    # Mo, who may read it, sees it in his open message; an administrator in the list.
    assert has_element?(watch(mod, target), "#forwarding", "Hidden plan")
    admin = user_with_role_fixture(:administrator)
    assert has_element?(watch(admin, target), "#message-#{sent.id}-forward", "Staff room")
    assert has_element?(watch(admin, target), "#message-#{sent.id}-forward", "Hidden plan")
  end

  test "a forwarder's own message shows to everyone, its topic hidden from those who may not view it",
       %{bea: bea, mod: mod, secret: secret, target: target} do
    {:ok, own} = Forum.post_message(mod, secret, %{"body" => "My own note"})
    {:ok, sent} = Messages.commit(mod, target, "Sharing mine", forwarded_from_id: own.id)

    view = watch(bea, target)
    forward = "#message-#{sent.id}-forward"
    assert has_element?(view, forward, "Mo message forwarded from a topic you cannot view")
    assert has_element?(view, forward, "My own note")
    refute render(view) =~ "Staff room"
  end

  test "!forward forwards the message replied to", %{bea: bea, source: source, tip: tip} do
    view = watch(bea, source)
    assert render_hook(view, "forward_quoted", %{}) =~ "Choose Reply on a message to forward it"
    refute has_element?(view, "#forward-dialog")

    view |> element("#message-#{tip.id}-reply") |> render_click()
    render_hook(view, "forward_quoted", %{})
    assert has_element?(view, "#forward-dialog", "Water them")
  end
end

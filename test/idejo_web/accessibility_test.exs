# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AccessibilityTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Moderation
  alias IdejoWeb.Accessibility

  setup do
    admin = user_with_role_fixture(:administrator)
    # RP-03: one category with an icon and a colour, the other as it was.
    {:ok, general} =
      Forum.create_category(admin, %{
        "name" => "General",
        "icon" => "general",
        "colour" => "#0fa05c"
      })

    # RP-03: a group, so pages show grouped sections and the sidebar's foldable groups.
    {:ok, group} = Forum.create_group(admin, %{"name" => "Off topic"})
    {:ok, _other} = Forum.create_category(admin, %{"name" => "Other", "group_id" => group.id})
    member = user_fixture(%{display_name: "Ada"})
    reader = user_fixture(%{display_name: "Bea"})

    {:ok, topic} =
      Forum.create_topic(member, general, %{
        "title" => "Garden plans",
        "body" => "Hi @#{reader.username}"
      })

    [first] = Forum.list_messages(topic)

    {:ok, reply} =
      Forum.post_message(reader, topic, %{"body" => "Yes", "reply_to_id" => first.id})

    {:ok, edited} = Forum.post_message(member, topic, %{"body" => "Monday"})
    {:ok, _} = Messages.edit(member, edited, "Tuesday")
    {:ok, gone} = Forum.post_message(member, topic, %{"body" => "Spam"})
    {:ok, _} = Messages.delete_as_moderator(admin, gone, "Spam")
    {:ok, _} = Moderation.report_message(reader, edited, %{"reason" => "Rude"})
    {:ok, _} = Accounts.create_invite(admin)
    # TP-19: a tag for every category and one of General's, on the topic.
    n = System.unique_integer([:positive])
    {:ok, idea} = Forum.Tags.create_tag(admin, %{"name" => "Idea #{n}"})

    {:ok, _} =
      Forum.Tags.create_tag(admin, %{"name" => "Seeds #{n}", "category_id" => general.id})

    {:ok, _} = Forum.set_topic_tags(admin, topic, [idea.id])

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    # TP-17: reactions under a message, and the reader's notification about them.
    {:ok, _} = Idejo.Reactions.toggle(member, reply, "agree")
    {:ok, _} = Idejo.Reactions.toggle(admin, reply, "agree")

    {:ok, _open} = Messages.commit(reader, topic, "Still typing")

    %{
      admin: admin,
      member: member,
      reader: reader,
      general: general,
      topic: topic,
      first: first,
      reply: reply,
      idea: idea
    }
  end

  # All pages are audited before failing, so one run lists every problem.
  defp assert_all_accessible(conn, paths) do
    report =
      for path <- paths,
          problems = Accessibility.audit(conn |> get(path) |> html_response(200)),
          problems != [],
          do: "#{path}:\n  " <> Enum.join(Enum.uniq(problems), "\n  ")

    assert report == [], Enum.join(report, "\n")
  end

  defp assert_accessible(conn, path), do: assert_all_accessible(conn, [path])

  @tag req: "AX-01"
  test "AX-01 public pages: landmarks, one h1, labels, names and keyboard use", %{
    conn: conn,
    general: general,
    topic: topic,
    member: member,
    reply: reply,
    idea: idea
  } do
    assert_all_accessible(conn, [
      ~p"/",
      ~p"/c/#{general.slug}",
      ~p"/t/#{topic.id}/#{topic.slug}",
      ~p"/t/#{topic.id}/#{topic.slug}?reply_to=#{reply.id}",
      ~p"/search",
      ~p"/search?q=garden",
      ~p"/tags",
      ~p"/rules",
      ~p"/tags?#{%{"tags" => [idea.slug]}}",
      ~p"/u/#{member.id}",
      # TP-10: the page a +role leads to.
      ~p"/r/moderator",
      ~p"/users/sign-in",
      ~p"/users/sign-up",
      ~p"/users/reset-password",
      ~p"/setup"
    ])
  end

  @tag req: "AX-01"
  test "AX-01 the welcome card a new member sees on their first visit", %{conn: conn} do
    conn = log_in_user(conn, user_fixture(%{welcome: true}))
    assert_all_accessible(conn, [~p"/", ~p"/rules"])
  end

  @tag req: "AX-01"
  test "AX-01 signed-in pages", %{
    conn: conn,
    general: general,
    reader: reader,
    first: first,
    reply: reply
  } do
    conn = log_in_user(conn, reader)

    assert_all_accessible(conn, [
      ~p"/",
      ~p"/unread",
      ~p"/notifications",
      ~p"/users/settings",
      ~p"/c/#{general.slug}/new",
      ~p"/m/#{reply.id}/new-topic",
      ~p"/m/#{first.id}/report"
    ])
  end

  @tag req: "AX-01"
  test "AX-01 moderation and admin pages", %{
    conn: conn,
    admin: admin,
    general: general,
    member: member,
    topic: topic
  } do
    conn = log_in_user(conn, admin)

    assert_all_accessible(conn, [
      # The topic page with "Moderate this topic" and "Edit tags" (TP-19).
      ~p"/t/#{topic.id}/#{topic.slug}",
      # The user card with its "User actions" (MO-02).
      ~p"/u/#{member.id}",
      ~p"/moderation",
      ~p"/moderation/log",
      ~p"/admin",
      ~p"/admin/email",
      ~p"/admin/users",
      ~p"/admin/users/#{admin.id}",
      ~p"/admin/invites",
      ~p"/admin/roles",
      ~p"/admin/categories",
      ~p"/admin/tags",
      ~p"/admin/stylesheet",
      ~p"/admin/permissions",
      ~p"/admin/permissions/#{general.slug}"
    ])
  end

  @tag req: "AX-01"
  test "AX-01 the audit finds what it looks for, so a passing page means something" do
    bad = """
    <!DOCTYPE html><html><head><title>x</title></head><body>
    <nav><a href="/">Home</a></nav><nav><a>No href</a></nav>
    <h2>Skipped h1</h2><h4>Deep</h4>
    <div phx-click="go">Click</div>
    <button></button><button aria-hidden="true"></button><button><span aria-hidden="true">x</span></button>
    <input id="q" type="text"><label for="missing">L</label>
    <img src="/a.png"><span tabindex="3">t</span>
    <p id="d"></p><p id="d"></p>
    <div class="hidden"><input id="unseen"></div>
    </body></html>
    """

    problems = Accessibility.audit(bad)

    for expected <- [
          "<html> has no lang",
          "0 <main> landmarks, not one",
          "no <footer>",
          "several <nav> landmarks without distinct aria-labels",
          "the first focusable element is not a link to <main>'s id",
          "0 <h1> headings, not one",
          "heading level skips from h2 to h4",
          ~s(id "d" is used 2 times),
          ~s(for="missing" on <label> names no element),
          "<a> is a link with no href",
          "<div> reacts to clicks but not to keys",
          ~s(<input id="q"> has no label),
          "<img> has no alt",
          "<span> has tabindex 3: it breaks the focus order"
        ] do
      assert expected in problems
    end

    # Two nameless buttons; the aria-hidden one and the hidden input are not counted.
    assert Enum.count(problems, &(&1 == "<button> has no accessible name")) == 2
    refute Enum.any?(problems, &(&1 =~ "unseen"))
  end

  @tag req: "AX-01"
  test "AX-01 the keyboard focus is always visible" do
    css = File.read!("assets/css/app.css")
    assert css =~ ~r/:focus-visible \{\s*outline: 2px solid/

    # An element that turns its outline off has a container that shows the focus instead.
    for [selector] <-
          Regex.scan(~r/([^{}]+)\{[^}]*outline:\s*(?:none|0)\b/, css, capture: :all_but_first) do
      assert String.trim(selector) == ".composer-input",
             "#{String.trim(selector)} hides the focus outline"
    end

    assert css =~ ~r/\.composer:focus-within \{\s*outline: 2px solid/
  end

  @tag req: "AX-01"
  test "AX-01 the live topic, with the composer, the editor and moderation controls", %{
    conn: conn,
    topic: topic,
    member: member,
    reader: reader,
    admin: admin
  } do
    path = ~p"/t/#{topic.id}/#{topic.slug}"

    # The author of an open message: the composer in its place.
    assert_accessible(log_in_user(conn, reader), path)
    # A moderator: every message has its moderation form.
    assert_accessible(log_in_user(build_conn(), admin), path)

    # Connected, with the message editor open and in Preview.
    {:ok, view, _html} =
      live_isolated(log_in_user(build_conn(), member), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    [edited | _] = for m <- Forum.list_messages(topic), m.edited, do: m
    view |> element("#message-#{edited.id} button", "Edit") |> render_click()
    assert_fragment_accessible(render(view), "#{path}, editing")
    # The Write / Preview tabs: only the selected one in the Tab order, arrows from the hook.
    assert has_element?(view, "[role=tablist][phx-hook=EditorTabs]")
    assert has_element?(view, "[role=tab][aria-selected=true][tabindex='0']", "Write")
    assert has_element?(view, "[role=tab][aria-selected=false][tabindex='-1']", "Preview")

    view |> element("#edit-message-#{edited.id} [id$=preview-tab]") |> render_click()
    assert_fragment_accessible(render(view), "#{path}, editor preview")
    assert has_element?(view, "[role=tab][aria-selected=true][tabindex='0']", "Preview")
    assert has_element?(view, "[role=tabpanel][aria-labelledby$=preview-tab]")
  end

  @tag req: "AX-01"
  test "AX-01 the focus moves into the message editor and back to Edit when it closes", %{
    topic: topic,
    member: member
  } do
    {:ok, view, _html} =
      live_isolated(log_in_user(build_conn(), member), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    [edited | _] = for m <- Forum.list_messages(topic), m.edited, do: m
    edit_button = "#message-#{edited.id}-edit"
    refute view |> element(edit_button) |> render() =~ "phx-mounted"

    view |> element(edit_button) |> render_click()
    form = view |> element("#edit-message-#{edited.id}") |> render()
    assert form =~ ~r/phx-mounted="[^"]*focus[^"]*#edit-message-#{edited.id} textarea/

    view |> element("#edit-message-#{edited.id} button", "Cancel") |> render_click()
    assert view |> element(edit_button) |> render() =~ ~r/phx-mounted="[^"]*focus/

    view |> element(edit_button) |> render_click()
    view |> form("#edit-message-#{edited.id}", edit: %{body: "Wednesday"}) |> render_submit()
    assert view |> element(edit_button) |> render() =~ ~r/phx-mounted="[^"]*focus/
  end

  defp assert_fragment_accessible(html, where) do
    problems = Accessibility.audit(html, page: false)
    assert problems == [], "#{where}:\n  " <> Enum.join(problems, "\n  ")
  end
end

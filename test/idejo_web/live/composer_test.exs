# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ComposerTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Repo

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    author = user_fixture(%{display_name: "Ada"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{conn: log_in_user(conn, author), topic: topic, author: author}
  end

  defp watch(conn, topic),
    do: live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

  defp enter(lv, body, break \\ false) do
    lv |> element("#composer") |> render_hook("commit", %{"body" => body, "break" => break})
  end

  defp items(lv) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#messages > li")
    |> LazyHTML.attribute("id")
  end

  @tag req: "GM-07"
  test "GM-07 the composer is only a text box whose placeholder names the keys", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    composer = lv |> element("#composer") |> render()

    assert composer =~
             "Enter: send · Shift+Enter: new line · Ctrl+Enter / Enter×3: New message"

    assert composer =~ "<textarea"
    refute composer =~ "<button"
    refute composer =~ ~r/\d+\s*s\b/
  end

  # Steward decision, 2026-10-25: bubbles beside the caret and in front of the timer line.
  @tag req: "GM-07"
  test "GM-07 bubbles say what Enter and Ctrl+Enter do, beside the caret and the timer line", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)

    assert has_element?(
             lv,
             ~s|#composer[data-label-send="Enter to send"][data-label-sent="Sent!"]|
           )

    assert has_element?(
             lv,
             ~s|#composer[data-label-continue="Continue typing to add to your message"]|
           )

    enter(lv, "Thinking aloud")

    assert has_element?(
             lv,
             ~s|#composer-timer #composer-timer-bubble[data-label-done="Ctrl+Enter to start new message"]|,
             "slow mode"
           )

    js = File.read!("assets/js/composer.js")
    assert js =~ "composer-caret"
    assert js =~ "labelSent"
    # No room beside the bubble for the hint: it goes below.
    assert js =~ ~s|hint.classList.add("is-below")|

    assert File.read!("assets/css/app.css") =~
             ~r/&\.is-below \{\s*position: absolute;\s*top: calc\(100% \+ 0\.375rem\)/

    timer = File.read!("assets/js/composer_timer.js")
    assert timer =~ "labelDone"

    # With "slow mode", three lines in turn, monospace like the hint (steward decision,
    # 2026-10-25).
    assert has_element?(
             lv,
             ~s|#composer-timer #composer-timer-hint.composer-hint[phx-update=ignore]|
           )

    assert lv |> element("#composer-timer-hint") |> render() =~
             ~s|data-labels="[&quot;You cannot start a new message...&quot;,&quot;...but you can continue the one above.&quot;,&quot;[Enter] to send always works.&quot;]"|

    # Under the line, centred, still; each line 3 s (steward decision, 2026-10-25).
    assert timer =~ "const HINT_MS = 3000"
    assert timer =~ "for (const el of [this.line, this.bubble])"

    [hint_css] =
      Regex.run(~r/^\.composer-timer-hint \{.*?^\}/ms, File.read!("assets/css/app.css"))

    assert hint_css =~ "top: calc(100% + 0.625rem)"
    assert hint_css =~ "text-align: center"
    refute hint_css =~ "animation"

    # After a send the hint first says the message is visible to all, for 2 s.
    assert has_element?(lv, ~s|#composer[data-label-visible="Message now visible to all!"]|)
    assert js =~ "const VISIBLE_MS = 2000"
    assert js =~ ~s|span("composer-hint", this.hintLabel())|

    # Theme colours only (steward decision, 2026-10-25), so a new theme recolours them. Dark
    # theme: tertiary outline, secondary text, on primary at 50% blurred 6px, the hint in
    # primary at 60%. Light theme: the primary's contrasting ink on primary at 75%.
    css = File.read!("assets/css/app.css")
    [bubble] = Regex.run(~r/^\.tutorial-bubble \{.*?^\}/ms, css)
    assert bubble =~ "border: 1px solid var(--bubble-line)"
    assert bubble =~ "color: var(--bubble-ink)"
    assert bubble =~ "background: var(--bubble-fill)"
    assert bubble =~ "backdrop-filter: blur(6px)"
    [light] = Regex.run(~r/^:root,\n\[data-theme="light"\] \{.*?^\}/ms, css)
    assert light =~ "--bubble-line: var(--color-accent)"
    assert light =~ "--bubble-ink: var(--color-primary-content)"
    assert light =~ "--bubble-fill: color-mix(in oklab, var(--color-primary) 75%, transparent)"
    [dark] = Regex.run(~r/^\[data-theme="dark"\] \{.*?^\}/ms, css)
    assert dark =~ "--bubble-ink: var(--color-secondary)"
    assert dark =~ "--bubble-fill: color-mix(in oklab, var(--color-primary) 50%, transparent)"
    assert dark =~ "--bubble-hint: color-mix(in oklab, var(--color-primary) 60%, transparent)"
    refute Regex.run(~r/^:root,\n\[data-theme="light"\] \{.*?^\}/ms, css) |> hd() =~ "#"

    assert css =~
             ~r/\.composer-hint \{[^}]*monospace[^}]*font-weight: 300[^}]*var\(--bubble-hint\)/s

    # "Sent!" starts white, text and outline, and turns to the theme's colours in a second.
    assert bubble =~ "animation: tutorial-bubble-sent 1s"

    assert css =~
             ~r/@keyframes tutorial-bubble-sent \{\s*from \{ color: #fff; border-color: #fff; \}/

    assert js =~ ~s|span("tutorial-bubble is-sent"|
    assert js =~ ~s|setProperty("--sent-delay"|

    # The account menu and the Help page turn them off.
    assert css =~
             ~r/\[data-bubbles="off"\] \.tutorial-bubble:not\(\.is-always\),\s*\[data-bubbles="off"\] \.composer-hint \{ display: none; \}/
  end

  @tag req: "GM-01"
  test "GM-01 Enter in the composer opens a message for everyone", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    {:ok, reader, _html} = watch(build_conn(), topic)

    enter(lv, "Hello")
    assert_reply(lv, %{closed: false, body: "Hello."})

    [_, message] = Forum.list_messages(topic)
    assert message.state == "open"
    assert has_element?(reader, "#message-#{message.id}", "Hello.")
  end

  @tag req: "GM-08"
  test "GM-08 the composer sits in place of the author's open message, replies below it", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    [first] = Forum.list_messages(topic)

    # With nothing open, the composer is at the end.
    assert items(lv) == ["message-#{first.id}", "composer-slot"]

    enter(lv, "Mine")
    [_, mine] = Forum.list_messages(topic)
    {:ok, reply} = Messages.commit(user_fixture(), topic, "Someone answers")

    # The composer is the open message, under the author's name; the reply comes below.
    assert items(lv) == ["message-#{first.id}", "message-#{mine.id}", "message-#{reply.id}"]
    assert has_element?(lv, "#message-#{mine.id} #composer")
    assert has_element?(lv, "#message-#{mine.id}", "Ada")

    # Appends keep it there.
    enter(lv, "Mine. Still mine")
    assert items(lv) == ["message-#{first.id}", "message-#{mine.id}", "message-#{reply.id}"]
  end

  @tag req: "GM-07"
  test "GM-07 readers see an open message like a closed one", %{conn: conn, topic: topic} do
    # The open state exists only as hidden text for assistive technology (AX-03), so that is
    # the one difference allowed.
    {:ok, lv, _html} = watch(conn, topic)
    {:ok, reader, _html} = watch(build_conn(), topic)

    enter(lv, "Same look")
    [first, open] = Forum.list_messages(topic)

    shape = fn id ->
      reader
      |> element("#message-#{id}")
      |> render()
      |> String.replace(~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "ID")
      |> String.replace(~r/<time.*?<\/time>/s, "TIME")
      |> String.replace(~r/<div[^>]*class="message-body"[^>]*>.*?<\/div>/s, "BODY")
      |> String.replace(~r/<a [^>]*class="author-name[^"]*">.*?<\/a>/s, "NAME")
      |> String.replace(~r/<span class="sr-only">.*?<\/span>/s, "")
    end

    assert shape.(open.id) == shape.(first.id)
    assert has_element?(reader, "#message-#{open.id} .sr-only", "(still being written)")
  end

  @tag req: "GM-05"
  test "GM-05 Ctrl+Enter after the window closes the message and the composer goes to the end",
       %{conn: conn, topic: topic} do
    {:ok, lv, _html} = watch(conn, topic)
    enter(lv, "Done")
    [_, mine] = Forum.list_messages(topic)

    mine
    |> Ecto.Changeset.change(closes_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    # Someone answered (else the unanswered message time applies).
    {:ok, _} = Idejo.Messages.commit(user_fixture(), topic, "Ok")
    enter(lv, "Done. Bye", true)
    assert_reply(lv, %{closed: true})

    assert Repo.reload!(mine).state == "closed"
    assert List.last(items(lv)) == "composer-slot"
    assert has_element?(lv, "#message-#{mine.id}", "Done. Bye.")
  end

  @tag req: "GM-05"
  test "GM-05 Ctrl+Enter within the window keeps the message open", %{conn: conn, topic: topic} do
    {:ok, lv, _html} = watch(conn, topic)
    enter(lv, "First line", true)
    assert_reply(lv, %{closed: false, body: "First line."})
  end

  # Steward decision, 2026-10-23: the line under the composer runs to when Ctrl+Enter may start
  # a new message: the unanswered message time alone, the window once someone wrote below.
  @tag req: "GM-05"
  test "GM-05 the line under the composer shows the time left before Ctrl+Enter works", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    refute has_element?(lv, "#composer-timer")
    enter(lv, "Thinking aloud")
    [_, mine] = Forum.list_messages(topic)

    ends = fn ->
      [value] =
        lv
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#composer-timer[phx-hook=ComposerTimer][aria-hidden=true]")
        |> LazyHTML.attribute("data-end")

      value |> String.to_integer() |> DateTime.from_unix!(:millisecond)
    end

    assert_in_delta DateTime.diff(ends.(), mine.opened_at, :millisecond), 600_000, 1

    {:ok, _} = Idejo.Messages.commit(user_fixture(), topic, "Go on")
    assert_in_delta DateTime.diff(ends.(), mine.opened_at, :millisecond), 15_000, 1

    # Complete: the line goes with the open message.
    Idejo.Messages.close(mine)
    _ = render(lv)
    refute has_element?(lv, "#composer-timer")
  end

  # Steward decision, 2026-10-25: appends by others burn in; the author typing below is told.
  @tag req: "GM-02"
  test "GM-02 others' appends burn in, and the composer counts the ones above it", %{
    conn: conn,
    topic: topic
  } do
    other = user_fixture()
    {:ok, theirs} = Messages.commit(other, topic, "Their start")
    {:ok, lv, _html} = watch(conn, topic)
    enter(lv, "Mine below")
    [_first, _theirs, mine] = Forum.list_messages(topic)

    # Nothing in the markup tells open from closed (GM-07): the hook burns what a body gains.
    assert has_element?(lv, "#message-#{theirs.id}-body[phx-hook=ShowAll]")
    refute render(lv) =~ "data-growing"

    # The bubble over the author's message, its labels from gettext.
    assert has_element?(
             lv,
             ~s|#message-#{mine.id} #composer-appended[phx-update=ignore][aria-hidden=true][data-label-one="1 message above has been appended"]|
           )

    assert has_element?(
             lv,
             ~s|#composer-appended[data-label-other="%{count} messages above have been appended"]|
           )

    show_all = File.read!("assets/js/show_all.js")
    assert show_all =~ "export function burnTail"
    assert show_all =~ ~s|new CustomEvent("idejo:appended"|

    js = File.read!("assets/js/composer.js")
    # Only appends above the composer, while it has the focus; scrolling up fades it.
    assert js =~ "Node.DOCUMENT_POSITION_FOLLOWING"
    assert js =~ "document.activeElement !== this.input"
    assert js =~ "if (window.scrollY < this.lastY && this.appended.size > 0) this.fadeAppended()"

    # Not a tutorial bubble: turning those off leaves it; the fade lasts 2 s.
    css = File.read!("assets/css/app.css")
    assert js =~ ~s|bubble.className = "tutorial-bubble is-always points-up"|
    assert css =~ ~s|[data-bubbles="off"] .tutorial-bubble:not(.is-always),|
    assert css =~ "& .is-fading { animation: composer-appended-fade 2s ease-out forwards; }"
  end

  # Steward decision, 2026-10-25: on phones the page pulled up at each send, hiding the box
  # under the keyboard.
  @tag req: "GM-02"
  test "GM-02 a send keeps the composer where it was, above the on-screen keyboard" do
    js = File.read!("assets/js/composer.js")
    # A repaint must not leave the page scrolled elsewhere: the scroll is taken before
    # anything changes and put back after the box is measured.
    assert js =~
             ~r/const y = window\.scrollY\s*this\.el\.style\.minHeight = `\$\{this\.el\.offsetHeight\}px`/

    assert js =~
             ~r/this\.input\.style\.height = "auto"\s*this\.input\.style\.height = this\.input\.scrollHeight \+ "px"\s*this\.el\.style\.minHeight = ""\s*if \(window\.scrollY !== y\) window\.scrollTo\(window\.scrollX, y\)/

    # The visible band excludes the keyboard; only a box seen when sent is kept in sight.
    assert js =~ "window.visualViewport"
    assert js =~ "const shown = this.inView()"
    assert length(Regex.scan(~r/if \(shown\) this\.reveal\(\)/, js)) == 2
  end

  # Steward report, 2026-10-25: on phones (Chrome, Firefox) the page still moved up and down
  # while typing and sending.
  @tag req: "GM-02"
  test "GM-02 typing and sending never change the page's height under the author" do
    js = File.read!("assets/js/composer.js")
    css = File.read!("assets/css/app.css")

    # The box keeps its height while it repaints, so the page never shrinks for a moment.
    assert js =~ "this.el.style.minHeight = `${this.el.offsetHeight}px`"

    # The hint's room below the box is kept, the largest, while the box has the focus.
    assert js =~
             "this.hintRoom = focused ? Math.max(this.hintRoom || 0, room) : room"

    refute js =~ ~s|this.el.style.paddingBottom = ""\n    const hint|

    # The backdrop, rewritten at every keystroke, is never the scroll anchor.
    [backdrop] = Regex.run(~r/^\.composer-backdrop \{.*?^\}/ms, css)
    assert backdrop =~ "overflow-anchor: none"

    # The slow mode hint's room under the timer line stays when the hint goes.
    assert css =~ ".composer-timer:has(.composer-timer-hint) { margin-bottom: 2rem; }"
    refute css =~ ".composer-timer:has(.composer-timer-hint:not([hidden]))"

    # The timer line's room is kept from before it starts to after it goes.
    assert css =~ "[data-js] .composer-timer-slot { min-height: calc(0.875rem + 2px + 2rem); }"
  end

  # Steward report, 2026-10-31: on phones the box jumped when the timer line started (the
  # author's name and the line appeared at the first Enter) and when it ended.
  @tag req: "GM-02"
  test "GM-02 the first Enter adds nothing above or below the box", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    assert has_element?(lv, "#composer-slot .message-head .author-name", "Ada")
    assert has_element?(lv, "#composer-slot .composer-timer-slot")
    refute has_element?(lv, "#composer-timer")

    enter(lv, "Hello")
    [_, mine] = Forum.list_messages(topic)
    assert has_element?(lv, "#message-#{mine.id} .message-head .author-name", "Ada")
    assert has_element?(lv, "#message-#{mine.id} .composer-timer-slot #composer-timer")
  end

  # Steward decision, 2026-10-25.
  @tag req: "GM-05"
  test "GM-05 Ctrl+Enter outside the box starts a new message when it may, else goes to the box" do
    js = File.read!("assets/js/composer.js")
    assert js =~ ~s|document.addEventListener("keydown", this.onPageKey)|
    assert js =~ ~s|document.removeEventListener("keydown", this.onPageKey)|
    # Never from other text fields, links or dialogs, which keep their own Ctrl+Enter.
    assert js =~
             ~s|const OWN_CTRL_ENTER = "input, textarea, select, [contenteditable], a[href], dialog[open]"|

    # A new message only when the timer line allows it (or in an edit); the caret in any case.
    assert js =~
             ~s|if (this.sent !== "" && (this.el.hasAttribute("data-editing") \|\| mayStartNew())) this.send(true)\n      this.focusEnd()|

    timer = File.read!("assets/js/composer_timer.js")
    assert timer =~ "export const mayStartNew = () => readyAt === null || Date.now() >= readyAt"
    assert timer =~ "readyAt = end + skew"
  end

  # Steward decision, 2026-10-23: the unanswered message time.
  @tag req: "GM-05"
  test "GM-05 alone below the last message, Ctrl+Enter after the window keeps it open", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    enter(lv, "Thinking aloud")
    [_, mine] = Forum.list_messages(topic)

    mine
    |> Ecto.Changeset.change(closes_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    enter(lv, "Thinking aloud. More", true)
    assert_reply(lv, %{closed: false, body: "Thinking aloud. More."})
    assert Repo.reload!(mine).state == "open"
  end

  @tag req: "GM-05"
  test "GM-05 three Enters in a row work as Ctrl+Enter, on touch screens too" do
    js = File.read!("assets/js/composer.js")
    assert js =~ "const ENTER_RUN = 3"
    assert js =~ "const ENTER_RUN_MS = 1000"
    # Every Enter counts, whatever the device; typing in between starts the count again.
    assert js =~ "this.send(e.ctrlKey || e.metaKey || this.enterRun())"
    assert js =~ ~r/addEventListener\("input", (\(\)|e) => \{\s*this.enters = 0/
    refute js =~ "No Ctrl+Enter on touch screens"
  end

  @tag req: "GM-02"
  test "GM-02 the server's text is the reply the composer keeps", %{conn: conn, topic: topic} do
    {:ok, lv, _html} = watch(conn, topic)
    enter(lv, "```\ncode")
    assert_reply(lv, %{closed: false, body: "```\ncode"})
  end

  @tag req: "GM-12"
  test "GM-12 after a reload the composer holds the open message again", %{
    conn: conn,
    topic: topic,
    author: author
  } do
    {:ok, _} = Messages.commit(author, topic, "Half a thought")
    html = conn |> get(~p"/t/#{topic.id}/chat") |> html_response(200)
    assert html =~ ~s(data-sent="Half a thought.")

    {:ok, lv, _html} = watch(conn, topic)
    assert_push_event(lv, "composer_sent", %{body: "Half a thought."})
  end

  # A browser that puts back what the box held before the reload must not show the message
  # twice (the sent text, then the same again as unsent).
  @tag req: "GM-12"
  test "GM-12 after a reload the open message is in the box once", %{conn: conn, topic: topic} do
    html = conn |> get(~p"/t/#{topic.id}/chat") |> html_response(200)
    assert html =~ ~r/<textarea[^>]*class="composer-input"[^>]*autocomplete="off"/

    js = File.read!("assets/js/composer.js")
    # Before the sent text is put back, what the browser restored is cut to what followed it.
    assert js =~
             ~s(this.input.value = keptAfterReload(this.input.value, this.el.dataset.sent || ""\))

    assert [_, mounted] = Regex.run(~r/mounted\(\) \{(.*?)\n  \},/s, js)
    [before_restore | _] = String.split(mounted, "this.restore(")
    assert before_restore =~ "keptAfterReload"

    # keptAfterReload/2, mirrored: only text typed after the sent text survives.
    kept = fn value, sent ->
      cond do
        sent == "" or value == "" ->
          ""

        String.starts_with?(value, sent <> " ") ->
          String.replace_prefix(value, sent <> " ", "")

        String.starts_with?(value, sent) ->
          value |> String.replace_prefix(sent, "") |> String.replace_prefix(" ", "")

        true ->
          ""
      end
    end

    assert kept.("Half a thought. ", "Half a thought.") == ""
    assert kept.("Half a thought. And more", "Half a thought.") == "And more"
    assert kept.("Half a thought.", "Half a thought.") == ""
    assert kept.("Something else", "Half a thought.") == ""
    assert kept.("Typed", "") == ""

    for line <- [
          ~s{if (sent === "" || value === "") return ""},
          ~s{if (value.startsWith(start)) return value.slice(start.length)},
          ~s{return value.startsWith(sent) ? value.slice(sent.length).replace(/^ /, "") : ""}
        ],
        do: assert(js =~ line)
  end

  @tag req: "GM-01"
  test "GM-01 a refused commit tells the composer", %{conn: conn, topic: topic} do
    {:ok, lv, _html} = watch(conn, topic)
    topic |> Ecto.Changeset.change(state: "locked") |> Repo.update!()

    enter(lv, "Too late")
    assert_reply(lv, %{error: true})
    refute has_element?(lv, "#composer")
  end

  @tag req: "GM-07"
  test "GM-07 the composer has no box: sent text reads as a message, unsent text is highlighted, text just sent burns in" do
    css = File.read!("assets/css/app.css")
    [composer] = Regex.run(~r/^\.composer \{.*?^\}/ms, css)
    refute composer =~ ~r/border:|background:/
    assert css =~ ~r/\.composer-unsent \{[^}]*box-shadow/s
    assert css =~ "@keyframes composer-burn"
    # White in a golden glow on the light theme, bright orange on the dark one.
    assert css =~ ~r/\.composer-burn \{\s*--burn-ink: #ffffff;\s*--burn-gold:/
    assert css =~ ~r/\[data-theme="dark"\] \.composer-burn \{ --burn-ink: oklch/
    assert css =~ ~r/prefers-reduced-motion: reduce\) \{\s*\.composer-burn \{ animation: none; \}/

    js = File.read!("assets/js/composer.js")
    assert js =~ "composer-burn"
    assert js =~ "export function burnMarks"
    # Repaints keep the burn's place through the DOM, never a style attribute (SP-05).
    assert js =~ "style.animationDelay"
  end

  # Steward decision, 2026-10-26: an image in the box shows as the excerpts' pill.
  @tag req: "TP-12"
  test "TP-12 an image's Markdown in the composer is drawn as an \"image:\" pill", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} = watch(conn, topic)
    assert has_element?(lv, ~s(#composer[data-label-image="image:"]))

    js = File.read!("assets/js/composer.js")
    assert js =~ "export function withImages"
    assert js =~ ~s|const runs = withImages(painted, value, this.el.dataset.labelImage|
    assert js =~ ~s|<span class="image-pill composer-image-pill">|

    # The Markdown stays under the textarea, unseen, so the caret keeps its place.
    css = File.read!("assets/css/app.css")
    assert css =~ ".composer-backdrop .composer-image {\n  color: transparent;"
    assert css =~ ".composer-image-pill {\n  position: absolute;"
  end
end

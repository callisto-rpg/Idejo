# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.GraphicalComposerTest do
  # "Use the graphical composer" (TP-11; steward decision, 2026-11-02): buttons under the
  # composer for emoji, images, text formatting, the other commands, and Send.
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Forum
  alias IdejoWeb.Accessibility

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Forum.create_topic(admin, general, %{"title" => "Chat", "body" => "Hi"})
    %{topic: topic, user: user_fixture()}
  end

  defp topic_live(user, topic) do
    {:ok, lv, _html} =
      live_isolated(log_in_user(build_conn(), user), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    lv
  end

  @tag req: "TP-11"
  test "TP-11 the graphical composer draws the message as it will look; the plain one does not",
       %{topic: topic, user: user} do
    # composer_view.js takes over the box's drawing where the composer says so.
    assert has_element?(topic_live(user, topic), ~s(#composer[data-graphical]))

    {:ok, plain} = Accounts.update_user_writing(user, %{graphical_composer: false})
    refute has_element?(topic_live(plain, topic), ~s(#composer[data-graphical]))
  end

  @tag req: "TP-11"
  test "TP-11 the graphical composer is a setting under Writing, on for new accounts", %{
    topic: topic,
    user: user
  } do
    # On for new accounts (steward decision, 2026-11-03), in the database's default too.
    assert user.graphical_composer
    assert has_element?(topic_live(user, topic), "#composer-toolbar")

    %{rows: [[default]]} =
      Idejo.Repo.query!(
        "SELECT column_default FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'graphical_composer'"
      )

    assert default == "true"

    {:ok, lv, html} = live(log_in_user(build_conn(), user), ~p"/users/settings")
    assert html =~ "Use the graphical composer"
    assert has_element?(lv, ~s(#writing-form input[name="writing[graphical_composer]"][checked]))

    assert lv
           |> form("#writing-form", writing: %{graphical_composer: "false"})
           |> render_submit() =~ "Writing preferences saved."

    refute Accounts.get_user(user.id).graphical_composer
    refute has_element?(lv, ~s(#writing-form input[name="writing[graphical_composer]"][checked]))

    # Read when a topic page opens.
    refute has_element?(topic_live(Accounts.get_user(user.id), topic), "#composer-toolbar")
  end

  @tag req: "TP-11"
  test "TP-11 the bar: emoji, image, text controls and + at the left, Send at the right", %{
    topic: topic,
    user: user
  } do
    {:ok, user} = Accounts.update_user_writing(user, %{"graphical_composer" => "true"})
    lv = topic_live(user, topic)

    # Hidden until the Composer hook shows it: without scripts nothing would run it.
    assert has_element?(lv, "#composer-toolbar[hidden][phx-update=ignore]")

    for selector <- [
          "#composer-emoji[data-tool=emoji]",
          "#composer-image[data-tool=image]",
          "#composer-format-toggle[aria-controls=composer-format][aria-expanded=false]",
          "#composer-more-toggle[aria-controls=composer-more][aria-expanded=false]",
          "#composer-send[aria-haspopup=menu]",
          "#composer-send-menu[role=menu][hidden] #composer-send-new[role=menuitem]"
        ] do
      assert has_element?(lv, selector), selector
    end

    for format <- ~w(newline bold italic strike link code quote list numbered) do
      assert has_element?(lv, "#composer-format[hidden] [data-format=#{format}][aria-label]")
    end

    # The other commands the author may use.
    for command <- ~w(spoiler poll schedule new-topic) do
      assert has_element?(lv, "#composer-more [data-command=#{command}]")
    end

    # Monochrome icons, every button named.
    assert lv |> element("#composer-send") |> render() =~ "hero-paper-airplane"
    problems = Accessibility.audit(render(lv), page: false)
    assert problems == [], Enum.join(problems, "\n")
  end

  @tag req: "TP-11"
  test "TP-11 + lists only the commands the author may use", %{topic: topic} do
    # A member who may not start topics anywhere: no "New topic from this".
    {:ok, user} =
      Accounts.update_user_writing(user_fixture(), %{"graphical_composer" => "true"})

    member = Idejo.Access.built_in_role!(:member)
    admin = user_with_role_fixture(:administrator)
    {:ok, _} = Idejo.Access.set_permission(admin, member, :server, :start, :unset)

    lv = topic_live(user, topic)
    assert has_element?(lv, "#composer-more [data-command=poll]")
    refute has_element?(lv, "#composer-more [data-command=new-topic]")
  end

  @tag req: "TP-11"
  test "TP-11 the emoji button opens the picker for the composer, not a reaction", %{
    topic: topic,
    user: user
  } do
    {:ok, user} = Accounts.update_user_writing(user, %{"graphical_composer" => "true"})
    lv = topic_live(user, topic)

    render_hook(lv, "emoji_picker", %{})
    assert has_element?(lv, "#emoji-picker-title", "Insert an emoji")
    refute has_element?(lv, "#emoji-picker-body[data-message-id]")
    problems = Accessibility.audit(render(lv), page: false)
    assert problems == [], Enum.join(problems, "\n")

    render_hook(lv, "close_picker", %{})
    refute has_element?(lv, "#emoji-picker")

    # A visitor has no composer: nothing opens.
    {:ok, visitor, _} =
      live_isolated(build_conn(), IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    render_hook(visitor, "emoji_picker", %{})
    refute has_element?(visitor, "#emoji-picker")
  end

  @tag req: "TP-11"
  test "TP-11 the script runs the bar: Send is Enter, its menu Ctrl+Enter" do
    js = File.read!("assets/js/composer_toolbar.js")
    assert File.read!("assets/js/composer.js") =~ "mountToolbar(this)"
    assert js =~ "hook.send(false)" and js =~ "hook.send(true)"

    for event <- ~w(contextmenu dblclick pointerdown) do
      assert js =~ "addEventListener(\"#{event}\""
    end

    # The emoji picker hands its choice to the composer.
    assert File.read!("assets/js/emoji_picker.js") =~ "idejo:emoji"
    assert js =~ "idejo:emoji"
  end
end

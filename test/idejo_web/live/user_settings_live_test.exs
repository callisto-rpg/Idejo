# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSettingsLiveTest do
  use IdejoWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Federation.Activity
  alias Idejo.Repo

  setup %{conn: conn} do
    user = user_fixture(%{display_name: "Ada Lovelace"})
    %{conn: log_in_user(conn, user), user: user}
  end

  defp updates(user) do
    Repo.all(from a in Activity, where: a.object_uri == ^user.uri and a.verb == "update")
  end

  @tag req: "AC-04"
  test "AC-04 visitors are sent to sign in" do
    assert {:error, {:redirect, %{to: "/users/sign-in"}}} =
             live(build_conn(), ~p"/users/settings")
  end

  @tag req: "AC-04"
  test "AC-04 a user changes their display name", %{conn: conn, user: user} do
    {:ok, lv, html} = live(conn, ~p"/users/settings")
    assert html =~ "@#{user.username}"

    assert {:error, {:redirect, %{to: "/users/settings"}}} =
             lv
             |> form("#profile-form", profile: %{display_name: "  Ada King  "})
             |> render_submit()

    user = Accounts.get_user(user.id)
    assert user.display_name == "Ada King"

    assert [%{payload: %{"type" => "Person", "name" => "Ada King"}, actor_uri: actor}] =
             updates(user)

    assert actor == user.uri

    # The header shows the new name after the page reloads.
    html = conn |> get(~p"/users/settings") |> html_response(200)
    assert html =~ ~s(class="account-name">Ada King)
  end

  @tag req: "AC-04"
  test "AC-04 the display name is required and at most 60 characters", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert lv |> form("#profile-form", profile: %{display_name: "   "}) |> render_submit() =~
             "can&#39;t be blank"

    assert lv
           |> form("#profile-form", profile: %{display_name: String.duplicate("a", 61)})
           |> render_change() =~ "should be at most 60 character"

    assert Accounts.get_user(user.id).display_name == "Ada Lovelace"
    assert updates(user) == []
  end

  @tag req: "AC-04"
  test "AC-04 saving an unchanged name records nothing", %{user: user} do
    assert {:ok, _} = Accounts.update_user_profile(user, %{"display_name" => "Ada Lovelace"})
    assert updates(user) == []
  end

  @tag req: "AC-04"
  test "AC-04 the username cannot be changed from the profile", %{user: user} do
    {:ok, updated} = Accounts.update_user_profile(user, %{"username" => "someone_else"})
    assert updated.username == user.username
  end

  # Steward decision, 2026-10-26: "Automatic punctuation" is each user's, no longer the
  # server's.
  @tag req: "GM-02"
  test "GM-02 a user turns automatic punctuation off in their profile, read by the composer",
       %{conn: conn, user: user} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Idejo.Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Idejo.Forum.create_topic(admin, general, %{"title" => "Chat", "body" => "Hi"})

    {:ok, lv, html} = live(conn, ~p"/users/settings")
    assert html =~ "Automatic punctuation"
    assert user.auto_punctuation

    assert has_element?(
             lv,
             ~s(#writing-form input[type="checkbox"][name="writing[auto_punctuation]"][checked])
           )

    {:ok, topic_lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    assert has_element?(topic_lv, ~s(#composer[data-punctuate="true"]))

    assert lv
           |> form("#writing-form", writing: %{auto_punctuation: "false"})
           |> render_submit() =~ "Writing preferences saved."

    refute Accounts.get_user(user.id).auto_punctuation
    refute has_element?(lv, ~s(#writing-form input[name="writing[auto_punctuation]"][checked]))

    {:ok, topic_lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    assert has_element?(topic_lv, ~s(#composer[data-punctuate="false"]))
  end

  # Steward decision, 2026-10-31: message actions always shown, on mobile and on desktop,
  # each off by default.
  @tag req: "AC-04"
  test "AC-04 a user chooses to always show message controls on mobile and on desktop",
       %{conn: conn, user: user} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Idejo.Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Idejo.Forum.create_topic(admin, general, %{"title" => "Chat", "body" => "Hi"})
    watch = fn -> live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id}) end

    {:ok, lv, html} = live(conn, ~p"/users/settings")
    assert html =~ "Show message controls on mobile"
    assert html =~ "Show message controls on desktop"
    refute user.controls_on_mobile or user.controls_on_desktop
    refute has_element?(lv, ~s(#controls-form input[type="checkbox"][checked]))

    {:ok, topic_lv, _html} = watch.()
    refute has_element?(topic_lv, "#messages[data-controls-mobile]")
    refute has_element?(topic_lv, "#messages[data-controls-desktop]")

    assert lv
           |> form("#controls-form", controls: %{controls_on_mobile: "true"})
           |> render_submit() =~ "Message controls saved."

    assert Accounts.get_user(user.id).controls_on_mobile
    {:ok, topic_lv, _html} = watch.()
    assert has_element?(topic_lv, "#messages[data-controls-mobile]")
    refute has_element?(topic_lv, "#messages[data-controls-desktop]")

    lv
    |> form("#controls-form",
      controls: %{controls_on_mobile: "false", controls_on_desktop: "true"}
    )
    |> render_submit()

    {:ok, topic_lv, _html} = watch.()
    refute has_element?(topic_lv, "#messages[data-controls-mobile]")
    assert has_element?(topic_lv, "#messages[data-controls-desktop]")

    # The stylesheet shows them in place or always; the tap script leaves them alone.
    css = File.read!("assets/css/app.css")
    assert css =~ "[data-controls-desktop] .message .message-actions { opacity: 1; }"
    assert css =~ "[data-js] #messages:not([data-controls-mobile]) .message .message-actions {"

    assert File.read!("assets/js/message_actions.js") =~
             ~s|message.closest("[data-controls-mobile]")|
  end

  @tag req: "AD-04"
  test "AD-04 Admin → Settings no longer has automatic punctuation" do
    admin = user_with_role_fixture(:administrator)
    {:ok, _lv, html} = live(log_in_user(build_conn(), admin), ~p"/admin")
    refute html =~ "Automatic punctuation"
  end
end

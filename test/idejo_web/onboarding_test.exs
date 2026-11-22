# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.OnboardingTest do
  @moduledoc """
  Onboarding (steward request, 2026-11-22), in **Admin → Onboarding and information**: the
  onboarding topic, always topical and followed by everyone, which moderators cannot delete
  while it is one; the default "Welcome" when there is none; and the new user presentation
  question, `{onboarding.string.1}`.
  """
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures
  import IdejoWeb.ApiHelpers, only: [pkce: 0, authorize_params: 1]
  import Phoenix.LiveViewTest

  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Forum.TopicIcons
  alias Idejo.Onboarding
  alias Idejo.Settings

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{admin: user_with_role_fixture(:administrator)}
  end

  test "the default waits for a category, then starts Welcome in the first one", %{
    admin: admin
  } do
    assert Onboarding.ensure() == {:error, :no_category}
    assert Onboarding.topic() == nil

    # The home page's order: Zeta, made first, comes before Alpha.
    {:ok, zeta} = Forum.create_category(admin, %{"name" => "Zeta"})
    {:ok, _alpha} = Forum.create_category(admin, %{"name" => "Alpha"})

    {:ok, topic} = Onboarding.ensure()
    assert topic.title == "Welcome"
    assert topic.category_id == zeta.id
    assert topic.topical
    assert topic.autofollow
    assert topic.icon.name == "Waving hand"
    assert Settings.get(:onboarding_topic_id) == topic.id

    [opening] = Forum.list_messages(topic)
    assert opening.body_md == "Welcome to idejo! Introduce yourself here."
    assert opening.anonymous
    starter = Idejo.Repo.get!(Idejo.Accounts.User, topic.author_id)
    assert starter.username == "idejo"
    assert starter.status == "system"

    # Once there, it stays: no second Welcome, no second hand.
    {:ok, again} = Onboarding.ensure()
    assert again.id == topic.id
    assert Enum.count(TopicIcons.list(), &(&1.name == "Waving hand")) == 1
  end

  test "the waving hand is reused when an administrator kept it", %{admin: admin} do
    {:ok, _} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, hand} = TopicIcons.create(admin, image_file(:png), %{"name" => "Waving hand"})

    {:ok, topic} = Onboarding.ensure()
    assert topic.icon_id == hand.id
    assert length(TopicIcons.list()) == 1
  end

  test "moderators cannot delete the onboarding topic while it is one", %{admin: admin} do
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, welcome} = Onboarding.ensure()
    moderator = user_with_role_fixture(:moderator)

    assert Forum.delete_topic(moderator, welcome) == {:error, :onboarding}
    assert Forum.delete_topic(admin, welcome) == {:error, :onboarding}
    assert Onboarding.topic()

    # Another topic chosen instead, the old one goes like any other.
    {:ok, other} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Say hello", "body" => "Hi"})

    {:ok, chosen} = Onboarding.choose(admin, other)
    assert chosen.id == other.id
    assert chosen.topical
    assert chosen.autofollow
    assert chosen.icon.name == "Waving hand"
    assert {:ok, _} = Forum.delete_topic(moderator, welcome)
  end

  test "nobody archives the onboarding topic while it is one", %{admin: admin} do
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, welcome} = Onboarding.ensure()
    moderator = user_with_role_fixture(:moderator)

    assert Forum.archive_topic(moderator, welcome) == {:error, :onboarding}
    assert Forum.archive_topic(admin, welcome) == {:error, :onboarding}
    assert Onboarding.topic().state == "open"

    # Nor with its category: deleting it may move the topics, not archive them.
    assert Forum.delete_category(admin, general, topics: :archive) == {:error, :onboarding}
    assert Onboarding.topic().category_id == general.id

    {:ok, other} = Forum.create_category(admin, %{"name" => "Other"})
    assert {:ok, _} = Forum.delete_category(admin, general, topics: {:move, other})
    assert Onboarding.topic().category_id == other.id

    # Once another topic is chosen, the old one archives like any other.
    attrs = %{"title" => "Say hello", "body" => "Hi"}
    {:ok, hello} = Forum.create_topic(user_fixture(), other, attrs)
    {:ok, _} = Onboarding.choose(admin, hello)
    assert {:ok, archived} = Forum.archive_topic(moderator, welcome)
    assert archived.state == "archived"
  end

  test "the web moderator form says why the onboarding topic stays", %{
    conn: conn,
    admin: admin
  } do
    {:ok, _} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, welcome} = Onboarding.ensure()

    conn = log_in_user(conn, user_with_role_fixture(:moderator))

    for params <- [%{"action" => "delete", "confirm" => "yes"}, %{"action" => "archive"}] do
      conn = post(conn, ~p"/t/#{welcome.id}/moderate", params)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "onboarding topic"
    end

    assert Onboarding.topic().state == "open"
  end

  test "only administrators choose or change it", %{admin: admin} do
    {:ok, _} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, welcome} = Onboarding.ensure()
    moderator = user_with_role_fixture(:moderator)

    assert Onboarding.choose(moderator, welcome) == {:error, :forbidden}
    assert Onboarding.update(moderator, %{"title" => "Hi"}) == {:error, :forbidden}
    assert Onboarding.save_question(moderator, "Who?") == {:error, :forbidden}
  end

  test "the admin page edits its category, icon and title, and the question", %{
    conn: conn,
    admin: admin
  } do
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, intro} = Forum.create_category(admin, %{"name" => "Introductions"})
    {:ok, star} = TopicIcons.create(admin, image_file(:png), %{"name" => "Star"})

    {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/admin/info-boxes")
    assert html =~ "Onboarding"
    assert html =~ "New user presentation question"
    assert html =~ "Now tell us a bit about yourself and why you joined this forum"

    # Opening the page started the default.
    welcome = Onboarding.topic()
    assert welcome.category_id == general.id
    assert has_element?(lv, "#onboarding-current", "Welcome")

    lv
    |> form("#onboarding-form",
      onboarding: %{category_id: intro.id, icon_id: star.id, title: "Hello there"}
    )
    |> render_submit()

    topic = Onboarding.topic()
    assert topic.id == welcome.id
    assert topic.category_id == intro.id
    assert topic.icon_id == star.id
    assert topic.title == "Hello there"
    assert topic.topical
    assert topic.autofollow

    lv
    |> form("#onboarding-question-form", question: %{text: "What brings you here?"})
    |> render_submit()

    assert Onboarding.string(1) == "What brings you here?"

    assert Enum.any?(
             Audit.list_entries(),
             &(&1.change == "settings.update" and
                 &1.after["onboarding_question"] == "What brings you here?")
           )
  end

  test "the admin page finds a topic and makes it the onboarding topic", %{
    conn: conn,
    admin: admin
  } do
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    attrs = %{"title" => "Introduce yourself", "body" => "Hi"}
    {:ok, other} = Forum.create_topic(user_fixture(), general, attrs)

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/info-boxes")

    lv |> form("#onboarding-search", query: "introduce") |> render_change()
    lv |> element("#onboarding-choose-#{other.id}") |> render_click()

    assert Settings.get(:onboarding_topic_id) == other.id
    assert has_element?(lv, "#onboarding-current", "Introduce yourself")
  end

  ## The tour (steward request, 2026-11-22)

  defp newcomer do
    {:ok, user} = Idejo.Accounts.mark_welcomed(user_fixture())
    user
  end

  defp tour(html) do
    found = html |> LazyHTML.from_document() |> LazyHTML.query("#onboarding-tour")

    if Enum.count(found) == 1,
      do: {LazyHTML.attribute(found, "data-step"), LazyHTML.attribute(found, "data-target")}
  end

  defp home(user) do
    conn = if user, do: log_in_user(build_conn(), user), else: build_conn()
    conn |> get(~p"/") |> html_response(200)
  end

  test "a new member is first pointed at the onboarding topic in the sidebar", %{
    conn: conn,
    admin: admin
  } do
    {:ok, _} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, welcome} = Onboarding.ensure()
    member = newcomer()

    html = conn |> log_in_user(member) |> get(~p"/") |> html_response(200)
    assert {["1"], [target]} = tour(html)
    assert target =~ ~s([data-topic-id="#{welcome.id}"])
    assert html =~ "Open a topic to get started."

    # Not before the welcome card is closed, nor for members who joined before (or finished
    # it), nor for visitors.
    refute tour(home(user_fixture(%{welcome: true})))
    {:ok, earlier} = Idejo.Accounts.mark_onboarded(newcomer())
    refute tour(home(earlier))
    refute tour(home(nil))
  end

  test "the app's sign-in page draws no tour, which would stop Allow", %{
    conn: conn,
    admin: admin
  } do
    {:ok, _} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, _welcome} = Onboarding.ensure()
    member = newcomer()
    {_verifier, challenge} = pkce()
    params = authorize_params(challenge)

    signed_in = log_in_user(conn, member)
    html = signed_in |> get(~p"/app/authorize?#{params}") |> html_response(200)
    assert html =~ "app-authorize-allow"
    refute tour(html)
    assert tour(signed_in |> get(~p"/") |> html_response(200))
  end

  test "on the onboarding topic: the composer, then the question, then the end", %{
    conn: conn,
    admin: admin
  } do
    {:ok, _} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, welcome} = Onboarding.ensure()
    {:ok, _} = Onboarding.save_question(admin, "Why are you here")
    member = newcomer()
    conn = log_in_user(conn, member)

    # The page itself leaves the first step out: the topic is open.
    page = conn |> get(~p"/t/#{welcome.id}/#{welcome.slug}") |> html_response(200)
    assert {["2"], ["#composer"]} = tour(page)

    {:ok, lv, html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => welcome.id})

    assert {["2"], ["#composer"]} = tour(html)
    assert html =~ "Type “Hi, I&#39;m #{member.display_name}” then press"

    lv |> element("#composer") |> render_hook("commit", %{"body" => "Hi", "break" => false})
    html = render(lv)
    assert {["3"], ["#composer"]} = tour(html)
    assert html =~ "Your message was sent."
    assert html =~ "Why are you here"
    refute Idejo.Repo.reload!(member).onboarded_at

    lv
    |> element("#composer")
    |> render_hook("commit", %{"body" => "Hi. I like dragons", "break" => true})

    html = render(lv)
    assert {["4"], ["#sidebar .sidebar-all"]} = tour(html)
    assert html =~ "continue the conversation in #Welcome"
    assert Idejo.Repo.reload!(member).onboarded_at

    # Finished: no step anywhere any more.
    refute tour(home(Idejo.Repo.reload!(member)))
  end

  test "no tour where the member may not post in the onboarding topic", %{
    conn: conn,
    admin: admin
  } do
    {:ok, _} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, welcome} = Onboarding.ensure()
    member = newcomer()
    assert tour(home(member))

    {:ok, _} = Forum.moderate_topic(admin, welcome, :lock)
    refute conn |> log_in_user(member) |> get(~p"/") |> html_response(200) |> tour()
  end

  test "the API tells the app about the tour, and the app finishes it", %{admin: admin} do
    {:ok, _} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, welcome} = Onboarding.ensure()
    member = newcomer()
    {token, _row} = IdejoWeb.ApiHelpers.api_token_fixture(member)

    api = fn method, path ->
      build_conn()
      |> IdejoWeb.ApiHelpers.api_conn(token)
      |> Phoenix.ConnTest.dispatch(@endpoint, method, path, %{})
      |> IdejoWeb.ApiHelpers.api_json(200)
    end

    assert api.(:get, "/api/v1/me")["onboarding"] == %{
             "topic_id" => welcome.id,
             "topic_title" => "Welcome",
             "question" => "Now tell us a bit about yourself and why you joined this forum"
           }

    assert api.(:post, "/api/v1/me/onboarded")["onboarding"] == nil
    assert Idejo.Repo.reload!(member).onboarded_at
    assert api.(:get, "/api/v1/me")["onboarding"] == nil
  end
end

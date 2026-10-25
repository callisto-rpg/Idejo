# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PushBannerTest do
  # Not async: a test turns push off server-wide.
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query
  import Idejo.AccountsFixtures

  alias Idejo.Forum
  alias Idejo.Push
  alias Idejo.Reading
  alias Idejo.Repo
  alias Idejo.Settings

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Picnic", "body" => "Saturday?"})

    %{admin: admin, general: general, topic: topic}
  end

  defp banner(conn, path) do
    conn
    |> get(path)
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("#push-banner")
  end

  @tag req: "PN-20"
  test "PN-20 offered to members who post or follow, after the welcome, unless dismissed", %{
    admin: admin,
    topic: topic
  } do
    refute Push.banner?(nil)

    # Neither posted nor follows.
    member = user_fixture()
    refute Push.banner?(member)

    :ok = Reading.follow(member, topic)
    assert Push.banner?(member)

    # Posting is enough too.
    poster = user_fixture()
    {:ok, _} = Forum.post_message(poster, topic, %{"body" => "Count me in"})
    assert Push.banner?(poster)

    # Never on the first page view after sign-up: while the welcome card shows.
    newcomer = user_fixture(%{welcome: true})
    :ok = Reading.follow(newcomer, topic)
    refute Push.banner?(newcomer)

    # "Not now": 14 days, kept on the server.
    {:ok, _} = Push.dismiss_banner(member)
    refute Push.banner?(member)

    Repo.update_all(from(p in Push.Preference, where: p.user_id == ^member.id),
      set: [banner_dismissed_at: DateTime.add(DateTime.utc_now(), -15, :day)]
    )

    assert Push.banner?(member)

    # Push off: never.
    {:ok, _} = Settings.update_settings(admin, %{"push_enabled" => "off"})
    refute Push.banner?(member)
  end

  @tag req: "PN-21"
  test "PN-21 a hidden bar under the header on category and topic pages only", %{
    general: general,
    topic: topic
  } do
    member = user_fixture()
    :ok = Reading.follow(member, topic)
    conn = log_in_user(build_conn(), member)

    for path <- [~p"/c/#{general.slug}", ~p"/t/#{topic.id}/#{topic.slug}"] do
      [banner] = conn |> banner(path) |> Enum.to_list()
      assert LazyHTML.attribute(banner, "hidden") == [""]

      assert LazyHTML.text(banner) =~
               "Get a notification when someone replies to you, mentions you or your role, or posts in topics you follow."

      assert banner |> LazyHTML.query("button.push-banner-turn-on") |> LazyHTML.text() =~
               "Turn on"

      assert banner |> LazyHTML.query("button.push-banner-not-now") |> LazyHTML.text() =~
               "Not now"
    end

    # In the column's flow, before the main content, never over it.
    html = conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200)
    assert html =~ ~r/id="push-banner".*<main id="main"/s

    # Not on other pages, nor for visitors.
    assert conn |> banner(~p"/") |> Enum.empty?()
    assert build_conn() |> banner(~p"/c/#{general.slug}") |> Enum.empty?()

    # "Not now" is recorded for the user.
    assert conn |> post(~p"/push/banner/dismiss") |> response(204)
    assert Push.preferences(member).banner_dismissed_at
    assert conn |> banner(~p"/c/#{general.slug}") |> Enum.empty?()

    js = File.read!("assets/js/push_banner.js")
    # Only "Turn on" asks for permission (through push.js), only when still undecided.
    assert js =~ ~s|Notification.permission !== "default"|
    assert js =~ "permission = await enablePush()"
    refute js =~ "requestPermission"
    refute File.read!("assets/js/push_banner.js") =~ ".focus({"
  end

  @tag req: "PN-22"
  test "PN-22 iPhone and iPad Safari tabs get the Home Screen steps, without Turn on", %{
    topic: topic
  } do
    member = user_fixture()
    :ok = Reading.follow(member, topic)

    [ios] =
      build_conn()
      |> log_in_user(member)
      |> banner(~p"/t/#{topic.id}/#{topic.slug}")
      |> LazyHTML.query("p.push-banner-ios")
      |> Enum.to_list()

    assert LazyHTML.text(ios) =~
             "To get notifications on iPhone, add Idejo to your Home Screen: tap Share, then Add to Home Screen, then open it from there."

    js = File.read!("assets/js/push_banner.js")
    assert js =~ "if (appleTouch() && !fromHomeScreen()) {"
    assert js =~ ~s|part(banner, "turn-on").hidden = true|
  end

  @tag req: "PN-23"
  test "PN-23 a named region, announced politely, never an alert", %{topic: topic} do
    member = user_fixture()
    :ok = Reading.follow(member, topic)

    [banner] =
      build_conn()
      |> log_in_user(member)
      |> banner(~p"/t/#{topic.id}/#{topic.slug}")
      |> Enum.to_list()

    assert LazyHTML.attribute(banner, "role") == ["region"]
    assert LazyHTML.attribute(banner, "aria-label") == ["Notifications"]
    assert LazyHTML.attribute(banner, "aria-live") == ["polite"]
    refute LazyHTML.to_html(banner) =~ ~s(role="alert")
    # Buttons: keyboard operable, with the visible focus every button has (AX-01).
    assert banner |> LazyHTML.query("button[type=button]") |> Enum.count() == 2
  end
end

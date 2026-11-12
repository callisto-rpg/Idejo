# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SharedSettingsTest do
  @moduledoc """
  Settings for all forums (steward request, 2026-11-13; `Idejo.Community.SharedSettings`):
  the group's inbox saves a member's Profile and account sections on every forum through
  the group's service; a forum takes them with a `settings` ticket, says its own page applies
  only there, and keeps shared notification choices read-only.
  """
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures
  import Phoenix.LiveViewTest

  alias Idejo.Accounts
  alias Idejo.Accounts.UserIdentity
  alias Idejo.Notifications.Digest
  alias Idejo.{Push, Repo}

  @issuer "https://id.example.test"
  @service "http://hub.example.test/internal/community"
  @settings "https://my.example.test/users/settings"
  @ticket String.duplicate("s", 32)

  setup do
    community = Application.get_env(:idejo, :community)
    oidc = Application.get_env(:idejo, :oidc)
    inbox = Application.get_env(:idejo, :inbox)

    on_exit(fn ->
      Application.put_env(:idejo, :community, community)
      Application.put_env(:idejo, :inbox, inbox)

      if oidc,
        do: Application.put_env(:idejo, :oidc, oidc),
        else: Application.delete_env(:idejo, :oidc)
    end)

    :ok
  end

  defp group(opts) do
    Application.put_env(:idejo, :inbox, opts[:inbox] == true)

    Application.put_env(:idejo, :community,
      url: @service,
      directory_url: nil,
      chat_url: opts[:chat_url],
      topics_url: nil,
      settings_url: opts[:settings_url]
    )

    Application.put_env(:idejo, :oidc,
      issuer: @issuer,
      client_id: "client",
      client_secret: "secret",
      label: "Example ID"
    )
  end

  defp link(user, subject) do
    Repo.insert!(UserIdentity.changeset(%{user_id: user.id, issuer: @issuer, subject: subject}))
    user
  end

  ## A forum

  defp vouch(scope) do
    Req.Test.stub(Idejo.Community, fn conn ->
      assert conn.request_path == "/internal/community/chats/tickets"
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      if JSON.decode!(body)["ticket"] == @ticket,
        do: Req.Test.json(conn, %{"subject" => "sub-ada", "scope" => scope}),
        else: conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
    end)
  end

  defp send_settings(body) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post(~p"/community/settings", JSON.encode!(body))
  end

  test "a forum saves what the inbox sent, with a settings ticket only" do
    group(chat_url: "https://my.example.test/chat")
    ada = link(user_fixture(), "sub-ada")
    picture = image_file(:png) |> File.read!() |> Base.encode64()

    settings = %{
      "profile" => %{"display_name" => "Ada King", "user_tag" => "maths", "username" => "x"},
      "bio" => %{"bio_md" => "Counting **engines**."},
      "avatar" => %{"light" => picture, "dark" => nil},
      "writing" => %{"auto_punctuation" => false, "graphical_composer" => false},
      "controls" => %{"controls_on_mobile" => true, "controls_on_desktop" => true},
      "private" => %{"accepts_private_messages" => false},
      "email" => %{"mentions" => false, "all_activity" => true, "once_a_week" => false},
      "push" => %{"reply" => false, "private" => false},
      "notifications_shared" => true
    }

    # Another scope's ticket writes nothing.
    vouch("topics")
    conn = send_settings(%{ticket: @ticket, settings: settings})
    assert json_response(conn, 404)
    assert Accounts.get_user(ada.id).display_name == ada.display_name

    vouch("settings")
    conn = send_settings(%{ticket: @ticket, settings: settings})

    assert %{"saved" => saved, "failed" => []} = json_response(conn, 200)

    assert saved ==
             ~w(profile bio avatar writing controls private email push notifications_shared)

    ada = Accounts.get_user(ada.id)
    assert {ada.display_name, ada.user_tag} == {"Ada King", "maths"}
    assert ada.username != "x"
    assert ada.bio_html =~ "<strong>engines</strong>"
    assert ada.avatar_id
    refute ada.auto_punctuation or ada.graphical_composer or ada.accepts_private_messages
    assert ada.controls_on_mobile and ada.controls_on_desktop
    assert ada.notifications_shared
    assert %{mentions: false, all_activity: true, once_a_week: false} = Digest.preferences(ada)
    assert %{reply: false, private: false, mention: true} = Push.preferences(ada)

    # A section that does not save leaves the others.
    conn =
      send_settings(%{
        ticket: @ticket,
        settings: %{"profile" => %{"display_name" => ""}, "bio" => %{"bio_md" => "Hi"}}
      })

    assert %{"saved" => ["bio"], "failed" => ["profile"]} = json_response(conn, 200)
  end

  test "without a chat service the address does not exist" do
    Application.put_env(:idejo, :community, url: nil, chat_url: nil)
    conn = send_settings(%{ticket: @ticket, settings: %{}})
    assert json_response(conn, 404)
  end

  test "a forum's page says it applies only here, and shared choices stay read-only", %{
    conn: conn
  } do
    group(chat_url: "https://my.example.test/chat", settings_url: @settings)
    ada = link(user_fixture(), "sub-ada")
    conn = log_in_user(conn, ada)

    {:ok, view, _html} = live(conn, ~p"/users/settings")
    assert has_element?(view, ~s(#shared-settings-link[href="#{@settings}"]))
    refute has_element?(view, "#email-locked")
    refute has_element?(view, ~s(button[name="everywhere"]))

    {:ok, ada} = Accounts.set_notifications_shared(ada, true)
    {:ok, view, _html} = live(conn, ~p"/users/settings?tab=messages")
    assert has_element?(view, ~s(#email-locked a[href="#{@settings}"]))
    assert has_element?(view, "#push-locked") or not Push.enabled?()
    assert has_element?(view, "#email-notifications-form fieldset[disabled]")

    html = render_submit(view, "save_email", %{"email" => %{"mentions" => "false"}})

    assert html =~ "These choices come from your settings for all forums."
    assert Digest.preferences(ada).mentions

    # Not linked to the provider: no note.
    other = user_fixture()
    {:ok, view, _html} = live(log_in_user(build_conn(), other), ~p"/users/settings")
    refute has_element?(view, "#shared-settings-note")
  end

  ## The inbox

  defp service(fun) do
    test = self()

    Req.Test.stub(Idejo.Community, fn conn ->
      assert conn.request_path == "/internal/community/inbox/settings"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:sent, JSON.decode!(body)})
      Req.Test.json(conn, fun.())
    end)
  end

  defp forum(name, answer \\ %{}),
    do: Map.merge(%{"name" => name, "answered" => true, "saved" => [], "failed" => []}, answer)

  test "the inbox saves a section here and on every forum", %{conn: conn} do
    group(inbox: true)
    ada = link(user_fixture(), "sub-ada")
    {:ok, view, _html} = live(log_in_user(conn, ada), ~p"/users/settings")
    Req.Test.allow(Idejo.Community, self(), view.pid)

    # Save keeps it here only.
    view |> form("#writing-form", writing: %{auto_punctuation: "false"}) |> render_submit()
    refute_received {:sent, _}
    refute Accounts.get_user(ada.id).auto_punctuation

    service(fn -> %{"forums" => [forum("Garden"), forum("Kitchen")]} end)

    html =
      view
      |> form("#controls-form", controls: %{controls_on_mobile: "true"})
      |> render_submit(%{"everywhere" => "true"})

    assert html =~ "Saved on all 2 of your forums too."
    assert_received {:sent, %{"subject" => "sub-ada", "settings" => settings}}

    assert settings == %{
             "controls" => %{"controls_on_mobile" => true, "controls_on_desktop" => false}
           }

    # A forum that did not answer is named.
    service(fn ->
      %{"forums" => [forum("Garden"), forum("Kitchen", %{"answered" => false})]}
    end)

    html =
      view
      |> form("#private-form", private: %{accepts_private_messages: "false"})
      |> render_submit(%{"everywhere" => "true"})

    assert html =~ "Not saved on Kitchen"
  end

  test "the inbox shares its notification choices with every forum", %{conn: conn} do
    group(inbox: true)
    ada = link(user_fixture(), "sub-ada")
    {:ok, view, _html} = live(log_in_user(conn, ada), ~p"/users/settings?tab=messages")
    Req.Test.allow(Idejo.Community, self(), view.pid)
    service(fn -> %{"forums" => [forum("Garden")]} end)

    html =
      view
      |> form("#shared-notifications-form", shared: %{notifications_shared: "true"})
      |> render_submit()

    assert html =~ "Your forums now use these email and push choices."
    assert Accounts.get_user(ada.id).notifications_shared
    assert_received {:sent, %{"settings" => settings}}
    assert settings["notifications_shared"] == true
    assert %{"email" => %{"mentions" => true}, "push" => %{"reply" => true}} = settings

    # While shared, each save of those choices goes everywhere, without asking.
    view
    |> form("#email-notifications-form", email: %{mentions: "false"})
    |> render_submit()

    assert_received {:sent, %{"settings" => %{"email" => %{"mentions" => false}} = settings}}
    assert settings["notifications_shared"] == true

    # Off: each forum keeps what it has.
    view
    |> form("#shared-notifications-form", shared: %{notifications_shared: "false"})
    |> render_submit()

    assert_received {:sent, %{"settings" => %{"notifications_shared" => false} = settings}}
    refute Map.has_key?(settings, "email")
  end

  test "the inbox offers nothing for all forums to a member not linked", %{conn: conn} do
    group(inbox: true)
    {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/users/settings")
    refute has_element?(view, ~s(button[name="everywhere"]))
    refute has_element?(view, "#avatar-everywhere")
    refute has_element?(view, "#shared-notifications-section")
  end
end

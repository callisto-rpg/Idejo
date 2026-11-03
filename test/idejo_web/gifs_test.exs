# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# GIFs in the composer (steward decisions, 2026-11-03): !gif and a GIF button opening an
# overlay that searches a swappable provider (KLIPY) from the browser. No requirement ID.
defmodule IdejoWeb.GifsTest do
  # Not async: the tests change the GIF settings, rows every test shares.
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Audit.Entry
  alias Idejo.Forum
  alias Idejo.Gifs
  alias Idejo.Gifs.Klipy
  alias Idejo.Messages.Automessages
  alias Idejo.Repo
  alias Idejo.Settings
  alias IdejoWeb.ComposerCommands

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Forum.create_topic(admin, general, %{"title" => "Chat", "body" => "Hi"})
    %{admin: admin, topic: topic}
  end

  defp turn_on(admin, attrs \\ %{}) do
    {:ok, _} =
      Settings.update_settings(admin, Map.merge(%{"gif_api_key" => "test-key-123"}, attrs))

    :ok
  end

  defp topic_live(user, topic) do
    {:ok, lv, _html} =
      live_isolated(log_in_user(build_conn(), user), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

    lv
  end

  defp policy(conn) do
    [policy] = get_resp_header(conn, "content-security-policy")
    policy |> String.split("; ") |> Map.new(&List.to_tuple(String.split(&1, " ", parts: 2)))
  end

  test "off until an administrator enters a key; KLIPY is the provider by default", %{
    admin: admin
  } do
    assert Gifs.provider() == Klipy
    refute Gifs.enabled?()
    assert Gifs.client_config() == nil
    assert Gifs.csp_sources() == %{connect: [], img: []}
    assert Settings.get(:gif_content_filter) == "medium"

    turn_on(admin, %{"gif_content_filter" => "high"})
    assert Gifs.enabled?()

    assert Gifs.client_config() == %{
             provider: "klipy",
             key: "test-key-123",
             filter: "high",
             placeholder: "Search KLIPY",
             name: "KLIPY",
             hosts: Klipy.media_sources()
           }

    # Audited like any setting (SP-06); a blank key turns GIFs off again.
    assert Entry
           |> Repo.all()
           |> Enum.any?(&(&1.admin_id == admin.id and &1.after["gif_api_key"] == "test-key-123"))

    {:ok, _} = Settings.update_settings(admin, %{"gif_api_key" => "  "})
    refute Gifs.enabled?()
    assert {:error, _} = Settings.update_settings(admin, %{"gif_content_filter" => "extreme"})
  end

  test "the security policy lets browsers reach only the provider's hosts, only while on", %{
    admin: admin
  } do
    off = policy(get(build_conn(), ~p"/"))
    assert off["img-src"] == "'self' data: blob:"
    assert off["connect-src"] == "'self'"

    turn_on(admin)
    on = policy(get(build_conn(), ~p"/"))
    assert on["connect-src"] == "'self' https://api.klipy.com"

    assert on["img-src"] ==
             "'self' data: blob: https://static.klipy.com https://static1.klipy.com https://static2.klipy.com"

    assert on["script-src"] =~ "'self' 'nonce-"
    refute on["script-src"] =~ "klipy"
  end

  test "with GIFs on, !gif, the GIF button and the overlay; without, none", %{
    admin: admin,
    topic: topic
  } do
    user = user_fixture()
    {:ok, user} = Accounts.update_user_writing(user, %{"graphical_composer" => "true"})

    lv = topic_live(user, topic)
    refute render(lv) =~ ~s("name":"gif")
    refute has_element?(lv, "#composer-gif")
    refute has_element?(lv, "#gif-picker")

    turn_on(admin)
    lv = topic_live(user, topic)
    commands = lv |> element("#composer") |> render()
    assert commands =~ "&quot;name&quot;:&quot;gif&quot;"
    assert commands =~ ~s(data-gif-hosts=)
    assert commands =~ "static.klipy.com"

    button = element(lv, "#composer-toolbar button#composer-gif[data-command=gif]")
    assert render(button) =~ ~s(aria-label="Add a GIF")

    picker =
      lv
      |> element(
        ~s(dialog#gif-picker[phx-hook=GifPicker][phx-update=ignore][aria-labelledby=gif-picker-title])
      )
      |> render()

    assert picker =~ ~s(data-provider="klipy")
    assert picker =~ ~s(data-key="test-key-123")
    assert picker =~ ~s(data-filter="medium")
    # KLIPY's attribution guidelines: "Search KLIPY" in the box (required), and the credit.
    assert picker =~ ~s(placeholder="Search KLIPY")
    assert picker =~ "Powered by KLIPY"
    assert picker =~ ~s(<label for="gif-search" class="sr-only">Search GIFs</label>)

    # Visitors and readers who may not post get none of it.
    {:ok, visitor, _html} =
      live_isolated(build_conn(), IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    refute has_element?(visitor, "#gif-picker")
  end

  test "!gif is one of the composer's commands, offered only while GIFs are on" do
    assert "gif" in Enum.map(ComposerCommands.all(), & &1.name)
    refute "gif" in Enum.map(ComposerCommands.for_composer(true, true, [], false), & &1.name)
    assert "gif" in Enum.map(ComposerCommands.for_composer(true, true, [], true), & &1.name)
    assert "gif" in Automessages.reserved()

    # Help lists it with the others.
    assert build_conn() |> get(~p"/help") |> html_response(200) =~ "!gif"
  end

  test "the browser side: the KLIPY adapter, the overlay and the composer" do
    klipy = File.read!("assets/js/gifs/klipy.js")
    assert klipy =~ ~s(const API = "https://api.klipy.com/api/v1")
    # Media URLs as returned, no user identifier, ads left out (they stay off for the key).
    assert klipy =~ ~S{gif.type !== "ad"}
    refute klipy =~ "customer_id"
    assert File.read!("assets/js/gifs/index.js") =~ "export const providers = {klipy}"

    picker = File.read!("assets/js/gif_picker.js")
    assert picker =~ ~S{window.addEventListener("idejo:gif-open", this.onOpen)}
    assert picker =~ ~S{new CustomEvent("idejo:gif"}

    composer = File.read!("assets/js/composer.js")
    assert composer =~ ~S{if (name === "gif")}
    assert composer =~ ~S{window.addEventListener("idejo:gif", this.onGif)}
    assert File.read!("assets/js/app.js") =~ "GifPicker,"
  end
end

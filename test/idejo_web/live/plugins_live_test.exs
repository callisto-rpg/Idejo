# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Plugins (steward request, 2026-11-08): no requirement ID. Not async: one plugins folder.
defmodule IdejoWeb.PluginsLiveTest do
  use IdejoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Plugins

  setup %{conn: conn} do
    File.rm_rf!(Plugins.dir())
    File.mkdir_p!(Plugins.dir())
    on_exit(fn -> File.rm_rf!(Plugins.dir()) end)
    Plugins.seed()

    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture(%{display_name: "Bo"})
    {:ok, topic} = Forum.create_topic(member, general, %{"title" => "Plans", "body" => "Ideas?"})

    %{conn: conn, admin: admin, member: member, topic: topic}
  end

  defp watch(conn, user, topic),
    do:
      live_isolated(log_in_user(conn, user), IdejoWeb.TopicLive,
        session: %{"topic_id" => topic.id}
      )

  defp commands(view) do
    [json] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#composer")
      |> LazyHTML.attribute("data-commands")

    Jason.decode!(json)
  end

  defp member_role, do: Access.built_in_role!(:member)

  test "Admin → Plugins turns plugins on and chooses who may use them", %{
    conn: conn,
    admin: admin,
    member: member,
    topic: topic
  } do
    {:ok, view, html} = live(log_in_user(conn, admin), ~p"/admin/plugins")
    assert html =~ "!youtube"
    assert html =~ "!card"

    view |> element("#plugin-youtube input[type=checkbox]") |> render_click()
    assert %{setting: %{enabled: true}} = Enum.find(Plugins.list(), &(&1.file == "youtube.json"))

    {:ok, member_view, _} = watch(conn, member, topic)
    refute Enum.any?(commands(member_view), &(&1["name"] == "youtube"))

    view |> element("#plugin-youtube-roles") |> render_click()
    assert has_element?(view, "#plugin-roles-dialog")

    view
    |> form("#plugin-roles-form", %{"role_ids" => [member_role().id]})
    |> render_submit()

    refute has_element?(view, "#plugin-roles-dialog")
    assert render(view) =~ "Roles saved for !youtube."

    {:ok, member_view, _} = watch(conn, member, topic)

    assert %{"plugin" => true, "argument" => "link", "label" => "!youtube"} =
             Enum.find(commands(member_view), &(&1["name"] == "youtube"))

    # Turned off again: gone from the composer.
    view |> element("#plugin-youtube input[type=checkbox]") |> render_click()
    {:ok, member_view, _} = watch(conn, member, topic)
    refute Enum.any?(commands(member_view), &(&1["name"] == "youtube"))
  end

  test "Add custom plugin installs an uploaded file", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/admin/plugins")
    view |> element("#add-plugin") |> render_click()

    text =
      Jason.encode!(%{
        idejo_plugin: 1,
        command: "docs",
        name: "Docs link",
        description: "A button to the docs",
        block: "button",
        argument: "text"
      })

    file =
      file_input(view, "#plugin-upload-form", :plugin, [
        %{name: "docs.json", content: text, type: "application/json"}
      ])

    render_upload(file, "docs.json")
    html = view |> form("#plugin-upload-form") |> render_submit()

    assert html =~ "!docs is installed."
    assert has_element?(view, "#plugin-docs")
    assert File.exists?(Path.join(Plugins.dir(), "docs.json"))
  end

  test "a plugin's command opens its dialog and adds its block under the author's message", %{
    conn: conn,
    admin: admin,
    member: member,
    topic: topic
  } do
    {:ok, _} = Plugins.set_enabled(admin, "button", true)
    {:ok, _} = Plugins.set_roles(admin, "button", [member_role().id])
    {:ok, _} = Plugins.set_enabled(admin, "card", true)
    {:ok, _} = Plugins.set_roles(admin, "card", [member_role().id])
    {:ok, view, _html} = watch(conn, member, topic)

    # Sent text, then the dialog for that message, with the typed label already in.
    render_hook(view, "commit", %{
      "body" => "Read this",
      "break" => false,
      "then" => "plugin",
      "plugin" => "button",
      "arg" => "Docs"
    })

    assert has_element?(view, "#plugin-dialog #plugin-label[value=Docs]")

    assert view
           |> form("#plugin-form", plugin: %{label: "Docs", url: "ftp://x"})
           |> render_submit() =~ "Give a link starting with https:// or http://."

    view
    |> form("#plugin-form", plugin: %{label: "Docs", url: "https://docs.example"})
    |> render_submit()

    refute has_element?(view, "#plugin-dialog")

    [_opening, message] = Forum.list_messages(topic)
    assert message.body_md == "Read this."
    assert has_element?(view, ~s(a.plugin-button[href="https://docs.example"]), "Docs")

    # A card: its button opens it.
    render_hook(view, "open_plugin", %{"name" => "card", "arg" => "Rules"})

    view
    |> form("#plugin-form", plugin: %{label: "Rules", body: "Be **kind**."})
    |> render_submit()

    view |> element("button.plugin-card-button", "Rules") |> render_click()
    assert has_element?(view, "#plugin-card strong", "kind")
    render_hook(view, "close_plugin_card", %{})
    refute has_element?(view, "#plugin-card")
  end

  test "!youtube:link: with nothing open posts the video at once; the policy lets it play", %{
    conn: conn,
    admin: admin,
    member: member,
    topic: topic
  } do
    {:ok, _} = Plugins.set_enabled(admin, "youtube", true)
    {:ok, _} = Plugins.set_roles(admin, "youtube", [member_role().id])
    {:ok, view, _html} = watch(conn, member, topic)

    render_hook(view, "open_plugin", %{
      "name" => "youtube",
      "arg" => "https://youtu.be/dQw4w9WgXcQ"
    })

    refute has_element?(view, "#plugin-dialog")

    assert has_element?(
             view,
             ~s(iframe.plugin-frame[src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"][sandbox])
           )

    [_opening, message] = Forum.list_messages(topic)
    assert message.author_id == member.id

    page = get(build_conn(), ~p"/t/#{topic.id}/#{topic.slug}")
    [policy] = get_resp_header(page, "content-security-policy")
    assert policy =~ "frame-src 'self' https://www.youtube-nocookie.com"

    # Its file deleted: the video goes, and so does the command.
    File.rm!(Path.join(Plugins.dir(), "youtube.json"))
    {:ok, view, _html} = watch(conn, member, topic)
    refute has_element?(view, "iframe.plugin-frame")
    refute Enum.any?(commands(view), &(&1["name"] == "youtube"))

    assert render_hook(view, "open_plugin", %{"name" => "youtube"}) =~
             "You cannot use this command here."

    # With no plugin on, pages no longer load what plugins added.
    refute :embeds in Messages.shown()
  end
end

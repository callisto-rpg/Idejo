# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Plugins (steward request, 2026-11-08): no requirement ID. Not async: one plugins folder.
defmodule Idejo.PluginsTest do
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Audit.Entry
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Plugins
  alias Idejo.Plugins.{Definition, Embed}

  setup do
    File.rm_rf!(Plugins.dir())
    File.mkdir_p!(Plugins.dir())
    on_exit(fn -> File.rm_rf!(Plugins.dir()) end)
    Plugins.seed()

    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Links", "body" => "Hi"})
    {:ok, message} = Messages.commit(author, topic, "Look at this")

    %{admin: admin, author: author, topic: topic, message: message}
  end

  defp on(admin, command, roles \\ []) do
    {:ok, _} = Plugins.set_enabled(admin, command, true)
    {:ok, _} = Plugins.set_roles(admin, command, Enum.map(roles, & &1.id))
  end

  defp member_role, do: Access.built_in_role!(:member)

  test "the bundled plugins are copied into the folder once, off; a deleted one stays deleted" do
    files = Plugins.dir() |> File.ls!() |> Enum.sort()
    assert files == ~w(button.json card.json iframe.json youtube.json)

    assert Enum.all?(Plugins.list(), &(&1.error == nil and &1.setting.enabled == false))
    assert Plugins.active() == %{}

    File.rm!(Path.join(Plugins.dir(), "card.json"))
    Plugins.seed()
    refute File.exists?(Path.join(Plugins.dir(), "card.json"))
    refute Enum.any?(Plugins.list(), &(&1.definition.command == "card"))
  end

  test "a plugin file is checked: bad files are listed with the reason, never used" do
    assert {:error, "The file is not valid JSON."} = Definition.parse("{")
    assert {:error, _} = Definition.parse(~s({"idejo_plugin": 1, "command": "Bad Name"}))

    assert {:error, reason} =
             Definition.parse(
               Jason.encode!(%{
                 idejo_plugin: 1,
                 command: "vids",
                 name: "Vids",
                 block: "video",
                 argument: "link",
                 video: %{match: ["^https://v\\.example/(\\w+)"], embed: "https://v.example/{id}"}
               })
             )

    assert reason =~ ~s(group named "id")

    assert {:error, reason} =
             Definition.parse(
               Jason.encode!(%{
                 idejo_plugin: 1,
                 command: "vids",
                 name: "Vids",
                 block: "video",
                 video: %{
                   match: ["^https://v\\.example/(?<id>\\w+)"],
                   embed: "http://v.example/{id}"
                 }
               })
             )

    assert reason =~ "https"

    File.write!(Path.join(Plugins.dir(), "broken.json"), "not json")
    # Another file for a command already taken, and one for a command of Idejo's own.
    File.write!(
      Path.join(Plugins.dir(), "zz-again.json"),
      File.read!(Path.join(Plugins.dir(), "button.json"))
    )

    File.write!(
      Path.join(Plugins.dir(), "poll.json"),
      ~s({"idejo_plugin": 1, "command": "poll", "name": "Poll", "block": "button"})
    )

    rows = Map.new(Plugins.list(), &{&1.file, &1})
    assert rows["broken.json"].definition == nil
    assert rows["zz-again.json"].error =~ "Another file"
    assert rows["poll.json"].error =~ "already a command"
  end

  test "turned on, a plugin is for owners, administrators and the roles chosen, where they may post",
       %{admin: admin, author: author, topic: topic} do
    assert Plugins.usable(admin, topic) == []
    on(admin, "button")
    assert [%{command: "button"}] = Plugins.usable(admin, topic)
    assert Plugins.usable(author, topic) == []

    on(admin, "button", [member_role()])
    assert [%{command: "button"}] = Plugins.usable(author, topic)
    assert Plugins.usable(nil, topic) == []

    {:ok, _} = Forum.moderate_topic(admin, topic, :lock, nil)
    assert Plugins.usable(author, Repo.reload!(topic)) == []

    changes = Repo.all(from e in Entry, where: like(e.change, "plugin.%"), select: e.change)
    assert "plugin.enable" in changes and "plugin.roles" in changes

    assert {:error, :not_found} = Plugins.set_enabled(admin, "nothing", true)
  end

  test "a YouTube link becomes a privacy-enhanced embed; other links are refused", %{
    admin: admin,
    author: author,
    topic: topic,
    message: message
  } do
    on(admin, "youtube", [member_role()])
    Messages.subscribe(topic.id)

    assert {:error, :link} =
             Plugins.attach(author, message, "youtube", %{"link" => "https://vimeo.com/1"})

    for link <- [
          "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
          "https://youtu.be/dQw4w9WgXcQ?t=3",
          "https://www.youtube.com/shorts/dQw4w9WgXcQ"
        ] do
      assert {:ok, _} = Plugins.attach(author, message, "youtube", %{"link" => link})
    end

    message_id = message.id
    assert_receive {:message, %{id: ^message_id, embeds: [_ | _]}}

    srcs = Repo.all(from e in Embed, where: e.message_id == ^message.id, select: e.data["src"])
    assert Enum.uniq(srcs) == ["https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"]

    assert Plugins.frame_sources() == ["https://www.youtube-nocookie.com"]
  end

  test "a frame keeps only an https address, never this server's", %{
    admin: admin,
    author: author,
    message: message
  } do
    on(admin, "iframe", [member_role()])
    own = Application.fetch_env!(:idejo, :base_uri) <> "/admin"

    for code <- ["http://example.com/", ~s(<iframe src="#{own}"></iframe>), "javascript:alert(1)"] do
      assert {:error, :code} = Plugins.attach(author, message, "iframe", %{"code" => code})
    end

    code =
      ~s|<iframe width="560" src="https://maps.example.org/embed?a=1&amp;b=2" onload="x()"></iframe>|

    assert {:ok, _} = Plugins.attach(author, message, "iframe", %{"code" => code})

    assert [%{block: "iframe", data: %{"src" => "https://maps.example.org/embed?a=1&b=2"}}] =
             Repo.all(from e in Embed, where: e.message_id == ^message.id)

    assert "https:" in Plugins.frame_sources()
  end

  test "buttons take an http(s) link; cards keep their Markdown and its sanitised HTML", %{
    admin: admin,
    author: author,
    message: message
  } do
    on(admin, "button", [member_role()])
    on(admin, "card", [member_role()])

    assert {:error, :label} =
             Plugins.attach(author, message, "button", %{
               "label" => " ",
               "url" => "https://a.example"
             })

    assert {:error, :url} =
             Plugins.attach(author, message, "button", %{"label" => "Go", "url" => "javascript:x"})

    assert {:ok, _} =
             Plugins.attach(author, message, "button", %{
               "label" => "Go",
               "url" => "https://a.example"
             })

    assert {:ok, _} =
             Plugins.attach(author, message, "card", %{
               "label" => "Rules",
               "body" => "**Be kind** <script>alert(1)</script>"
             })

    card = Repo.one!(from e in Embed, where: e.block == "card")
    assert card.data["body_html"] =~ "<strong>Be kind</strong>"
    refute card.data["body_html"] =~ "<script"
  end

  test "only the author adds to their message, at most ten blocks", %{
    admin: admin,
    author: author,
    message: message
  } do
    on(admin, "button", [member_role()])
    params = %{"label" => "Go", "url" => "https://a.example"}

    assert {:error, :forbidden} = Plugins.attach(user_fixture(), message, "button", params)
    for _ <- 1..10, do: assert({:ok, _} = Plugins.attach(author, message, "button", params))
    assert {:error, :too_many} = Plugins.attach(author, message, "button", params)
  end

  test "with nothing to go under, the block is posted as a message of its own", %{
    admin: admin,
    author: author,
    topic: topic
  } do
    on(admin, "youtube", [member_role()])
    link = "https://youtu.be/dQw4w9WgXcQ"

    assert {:error, :link} = Plugins.post(author, topic, "youtube", %{"link" => "nope"})
    assert {:ok, message} = Plugins.post(author, topic, "youtube", %{"link" => link})
    assert message.body_md == link
    assert message.state == "closed"
  end

  test "a plugin whose file is deleted or turned off leaves the messages it was used in", %{
    admin: admin,
    author: author,
    message: message
  } do
    on(admin, "button", [member_role()])

    {:ok, _} =
      Plugins.attach(author, message, "button", %{"label" => "Go", "url" => "https://a.example"})

    embeds = Repo.preload(message, :embeds, force: true).embeds
    assert [_] = Plugins.shown(embeds, Plugins.active())

    File.rm!(Path.join(Plugins.dir(), "button.json"))
    assert Plugins.shown(embeds, Plugins.active()) == []
    assert Plugins.usable(admin, Repo.get!(Forum.Topic, message.topic_id)) == []
  end

  test "an administrator installs a plugin file, off; the same command twice is refused", %{
    admin: admin
  } do
    text =
      Jason.encode!(%{
        idejo_plugin: 1,
        command: "vimeo",
        name: "Vimeo video",
        description: "A Vimeo video",
        block: "video",
        argument: "link",
        video: %{
          match: ["^https://vimeo\\.com/(?<id>\\d+)"],
          embed: "https://player.vimeo.com/video/{id}"
        }
      })

    assert {:ok, %{command: "vimeo"}} = Plugins.install(admin, text)
    assert File.exists?(Path.join(Plugins.dir(), "vimeo.json"))
    assert %{setting: %{enabled: false}} = Enum.find(Plugins.list(), &(&1.file == "vimeo.json"))
    assert {:error, reason} = Plugins.install(admin, text)
    assert reason =~ "installed already"
    assert {:error, "The file is not valid JSON."} = Plugins.install(admin, "{")

    assert Repo.exists?(from e in Entry, where: e.change == "plugin.install")
  end
end

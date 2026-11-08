# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Plugins !collapse and !forum (steward request, 2026-11-09): no requirement ID. Not async:
# one plugins folder.
defmodule Idejo.PluginsFoldsForumTest do
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Plugins
  alias Idejo.Plugins.{Definition, Embed, Folds}
  alias Idejo.Uploads

  setup do
    File.rm_rf!(Plugins.dir())
    File.mkdir_p!(Plugins.dir())
    on_exit(fn -> File.rm_rf!(Plugins.dir()) end)
    Plugins.seed()

    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    author = user_fixture()
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "Clubs", "body" => "Hi"})

    %{admin: admin, author: author, topic: topic}
  end

  defp on(admin, command) do
    {:ok, _} = Plugins.set_enabled(admin, command, true)
    {:ok, _} = Plugins.set_roles(admin, command, [Access.built_in_role!(:member).id])
  end

  describe "folds" do
    test "the command's line is the title; the : lines right below fold under it" do
      assert [
               {:text, "Intro"},
               {:fold, "Spoilers", "The butler.\nHe had the key."},
               {:text, "After"}
             ] =
               Folds.split(
                 "Intro\n!collapse Spoilers\n:The butler.\n: He had the key.\nAfter",
                 ["collapse"]
               )

      # The title on the next line; two folds.
      assert [{:fold, "Title", "a"}, {:fold, "Two", "b"}] =
               Folds.split("!collapse\nTitle\n:a\n!collapse Two\n:b", ["collapse"])

      # No : line, another command, inside code, or not at the line's start: plain text.
      assert Folds.split("!collapse Title\nnothing hidden", ["collapse"]) == nil
      assert Folds.split("!fold Title\n:a", ["collapse"]) == nil
      assert Folds.split("```\n!collapse Title\n:a\n```", ["collapse"]) == nil
      assert Folds.split("say !collapse Title\n:a", ["collapse"]) == nil
      assert Folds.split("!collapse Title\n:a", []) == nil
    end

    test "a message's folds become <details>, for authors who may use the plugin, and stay", %{
      admin: admin,
      author: author,
      topic: topic
    } do
      text = "Read on\n!collapse **Chapter 3**\n:The butler did it.\n:He had the key."

      {:ok, plain} = Messages.commit(author, topic, text, break: true)
      refute plain.body_html =~ "<details"

      on(admin, "collapse")
      {:ok, folded} = Messages.commit(author, topic, text <> "\n:Then he ran.", break: true)

      assert folded.body_html =~
               ~s(<details class="message-fold"><summary><strong>Chapter 3</strong></summary>)

      assert folded.body_html =~
               "<p>The butler did it.\nHe had the key.\nThen he ran.</p></details>"

      assert folded.body_html =~ "<p>Read on</p>"
      refute folded.body_html =~ "!collapse"

      # Its plugin gone, what was written stays folded (steward decision).
      File.rm!(Path.join(Plugins.dir(), "collapse.json"))
      assert Repo.reload!(folded).body_html == folded.body_html
      assert Plugins.fold_commands(author_id: author.id) == []
    end

    test "a script in a title or a fold is never kept", %{
      admin: admin,
      author: author,
      topic: topic
    } do
      on(admin, "collapse")

      {:ok, message} =
        Messages.commit(author, topic, "!collapse <script>x()</script>\n:<img src=x onerror=y>",
          break: true
        )

      assert message.body_html =~ "<details"
      refute message.body_html =~ "<script"
      refute message.body_html =~ "onerror"
    end
  end

  describe "forum" do
    setup %{admin: admin} do
      on(admin, "forum")
      [definition] = for %{definition: %{command: "forum"} = d} <- Plugins.list(), do: d
      # The bundled file names forums.idejo.org; tests ask a directory of their own.
      %{definition: %{definition | directory: "https://forums.idejo.test"}}
    end

    defp directory(forums) do
      test_pid = self()
      png = File.read!(image_file(:png))

      Req.Test.stub(Idejo.Plugins, fn conn ->
        send(test_pid, {conn.host, conn.request_path, conn.query_string})

        case conn.request_path do
          "/api/forums" ->
            Req.Test.json(conn, %{forums: forums})

          "/logo" ->
            conn |> Plug.Conn.put_resp_content_type("image/png") |> Plug.Conn.send_resp(200, png)
        end
      end)
    end

    @garden %{
      "name" => "Garden club",
      "url" => "https://garden.idejo.test/",
      "logo" => "https://garden.idejo.test/logo",
      "join" => "https://garden.idejo.test/users/oidc"
    }

    test "the directory's answers are checked: five at most, Join and logo on the forum's host",
         %{definition: definition} do
      directory(
        [
          @garden,
          %{
            "name" => "Elsewhere",
            "url" => "https://a.example/",
            "logo" => "https://b.example/x"
          },
          %{"name" => "", "url" => "https://c.example/"},
          %{"name" => "Plain", "url" => "http://d.example/"}
        ] ++ for(n <- 1..6, do: %{"name" => "Club #{n}", "url" => "https://club#{n}.example/"})
      )

      results = Plugins.search_forums(definition, "  club ")
      assert_receive {_host, "/api/forums", "q=club"}
      assert length(results) == 5
      assert hd(results) == @garden

      assert Enum.at(results, 1) == %{
               "name" => "Elsewhere",
               "url" => "https://a.example/",
               "join" => "https://a.example/",
               "logo" => nil
             }
    end

    test "a directory leading inside this network is never asked", %{definition: definition} do
      directory([@garden])
      inside = %{definition | directory: "https://inside.idejo.test"}
      assert Plugins.search_forums(inside, "") == []
      refute_receive {_, _, _}
    end

    test "the chosen forum goes under the message as a card, its logo copied here", %{
      author: author,
      topic: topic
    } do
      directory([@garden])
      {:ok, message} = Messages.commit(author, topic, "Come and see")

      assert {:error, :forum} =
               Plugins.attach(author, message, "forum", %{"forum" => %{"name" => "x"}})

      assert {:ok, _} = Plugins.attach(author, message, "forum", %{"forum" => @garden})
      assert_receive {_host, "/logo", _}

      [embed] = Repo.all(from e in Embed, where: e.message_id == ^message.id)
      assert embed.block == "forum"

      assert %{"name" => "Garden club", "join" => "https://garden.idejo.test/users/oidc"} =
               embed.data

      assert "/uploads/" <> name = embed.data["logo"]
      assert String.ends_with?(name, ".webp")

      # Kept by the nightly clean-up while the card names it.
      Uploads.delete_unused(DateTime.add(DateTime.utc_now(), 1, :day))
      assert Repo.exists?(from u in Uploads.Upload, where: u.path == ^name)
    end

    test "a forum plugin needs an https directory" do
      text = fn directory ->
        Jason.encode!(%{
          idejo_plugin: 1,
          command: "club",
          name: "Club",
          block: "forum",
          directory: directory
        })
      end

      assert {:ok, %{directory: "https://dir.example"}} =
               Definition.parse(text.("https://dir.example/"))

      assert {:error, _} = Definition.parse(text.("http://dir.example"))
      assert {:error, _} = Definition.parse(text.(nil))
    end
  end
end

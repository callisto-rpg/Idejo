# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.FirstMessageEditorTest do
  use IdejoWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Federation.Activity
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages.Message
  alias Idejo.Repo

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, _general} = Forum.create_category(admin, %{"name" => "General"})
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp type(lv, title, body) do
    lv |> form("#new-topic-form", topic: %{title: title, body: body}) |> render_change()
  end

  @tag req: "TP-02"
  test "TP-02 the first message is written in the message editor, with a preview", %{
    conn: conn
  } do
    {:ok, lv, _html} = live(conn, ~p"/c/general/new")
    assert has_element?(lv, "#topic_body-editor textarea[name='topic[body]']")
    assert has_element?(lv, "#topic_body-write-tab[aria-selected=true]")

    type(lv, "Plans", "Some **bold** words <script>alert(1)</script>")
    lv |> element("#topic_body-preview-tab") |> render_click()

    assert has_element?(lv, "#topic_body-preview-tab[aria-selected=true]")
    preview = lv |> element("#topic_body-preview") |> render()
    assert preview =~ "<strong>bold</strong>"
    refute preview =~ "<script"

    # The text stays in the form while previewing, and back in Write it is unchanged.
    assert has_element?(lv, "textarea[name='topic[body]']", "Some **bold** words")
    lv |> element("#topic_body-write-tab") |> render_click()
    refute has_element?(lv, "#topic_body-preview")
  end

  @tag req: "TP-11"
  test "TP-11 the preview shows Markdown and code blocks as they will be posted", %{
    conn: conn
  } do
    {:ok, lv, _html} = live(conn, ~p"/c/general/new")
    type(lv, "Code", "A *list*:\n\n- one\n\n```\nIO.puts(:hi)\n```")
    lv |> element("#topic_body-preview-tab") |> render_click()

    preview = lv |> element("#topic_body-preview") |> render()
    assert preview =~ "<em>list</em>"
    assert preview =~ "<li>one</li>"
    assert preview =~ ~r/<pre[^>]*><code[^>]*>IO.puts\(:hi\)/
  end

  @tag req: "TP-02"
  test "TP-02 nobody sees the first message while it is typed", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/c/general/new")
    type(lv, "Secret plans", "Not ready yet")
    lv |> element("#topic_body-preview-tab") |> render_click()

    # Nothing is stored or announced before posting.
    refute Repo.exists?(Topic)
    refute Repo.exists?(Message)

    refute Repo.exists?(
             from a in Activity, where: a.verb == "create" and not is_nil(a.target_uri)
           )

    for viewer <- [build_conn(), log_in_user(build_conn(), user_fixture())] do
      refute viewer |> get(~p"/c/general") |> html_response(200) =~ "Secret plans"
    end
  end

  @tag req: "TP-02"
  test "TP-02 it is posted closed together with the title, even from the preview", %{
    conn: conn
  } do
    {:ok, lv, _html} = live(conn, ~p"/c/general/new")
    type(lv, "Ready", "Now it *is*")
    lv |> element("#topic_body-preview-tab") |> render_click()

    lv
    |> form("#new-topic-form", topic: %{title: "Ready", body: "Now it *is*"})
    |> render_submit()

    assert [%Topic{title: "Ready"} = topic] = Repo.all(Topic)
    assert [message] = Forum.list_messages(topic)
    assert message.state == "closed"
    assert message.opened_at == message.closed_at
    assert message.body_md == "Now it *is*"
  end

  @tag req: "TP-02"
  test "TP-02 an empty preview says so", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/c/general/new")
    lv |> element("#topic_body-preview-tab") |> render_click()
    assert lv |> element("#topic_body-preview") |> render() =~ "Nothing to preview yet."
  end
end

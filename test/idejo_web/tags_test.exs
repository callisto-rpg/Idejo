# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.TagsTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Forum.Tags
  alias Idejo.Repo

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, staff} = Forum.create_category(admin, %{"name" => "Staff"})
    n = System.unique_integer([:positive])
    {:ok, alpha} = Tags.create_tag(admin, %{"name" => "Alpha #{n}"})
    {:ok, beta} = Tags.create_tag(admin, %{"name" => "Beta #{n}", "category_id" => general.id})
    {:ok, secret} = Tags.create_tag(admin, %{"name" => "Secret #{n}", "category_id" => staff.id})
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:guest), staff, :view, :deny)
    {:ok, _} = Access.set_permission(admin, Access.built_in_role!(:member), staff, :view, :deny)

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{
      conn: conn,
      admin: admin,
      general: general,
      staff: staff,
      alpha: alpha,
      beta: beta,
      secret: secret
    }
  end

  defp topic!(category, title, tags) do
    {:ok, topic} =
      Forum.create_topic(user_fixture(), category, %{
        "title" => title,
        "body" => "Hi",
        "tag_ids" => Enum.map(tags, & &1.id)
      })

    topic
  end

  defp titles(html, selector \\ "#topics li > a") do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

  @tag req: "TP-19"
  test "TP-19 a tag's link opens Filter by tag with it chosen; topics carry all chosen tags", %{
    conn: conn,
    general: general,
    alpha: alpha,
    beta: beta,
    secret: secret
  } do
    both = topic!(general, "Both tags", [alpha, beta])
    topic!(general, "Alpha only", [alpha])

    page = conn |> get(~p"/t/#{both.id}/#{both.slug}") |> html_response(200)
    link = "/tags?tags[]=#{alpha.slug}"
    assert page =~ ~s(href="#{Plug.HTML.html_escape(link)}")

    html = conn |> get(link) |> html_response(200)
    assert html =~ "Filter by tag"
    assert titles(html) |> Enum.sort() == ["Alpha only", "Both tags"]

    checked =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s(#tag-filter input[checked]))
      |> LazyHTML.attribute("value")

    assert checked == [alpha.slug]

    html = conn |> get(~p"/tags?#{%{"tags" => [alpha.slug, beta.slug]}}") |> html_response(200)
    assert titles(html) == ["Both tags"]

    # Visitors are not offered tags of categories they may not view.
    refute html =~ secret.name

    html = conn |> get(~p"/tags?#{%{"tags" => [secret.slug]}}") |> html_response(200)
    assert titles(html) == []
    refute html =~ "id=\"tagged-heading\""
  end

  # The Operator toggle (steward decision, 2026-10-24): And (the default) or Or, submit
  # buttons styled as the View toggle.
  @tag req: "TP-19"
  test "TP-19 the Operator toggle switches between all chosen tags (And) and any (Or)", %{
    conn: conn,
    general: general,
    alpha: alpha,
    beta: beta
  } do
    topic!(general, "Both tags", [alpha, beta])
    topic!(general, "Alpha only", [alpha])
    topic!(general, "Beta only", [beta])
    tags = [alpha.slug, beta.slug]

    doc = conn |> get(~p"/tags?#{%{"tags" => tags}}") |> html_response(200)
    assert titles(doc) == ["Both tags"]
    doc = LazyHTML.from_document(doc)

    assert texts(doc, "#tag-filter .view-toggle > .view-toggle-label") == ["Operator"]
    assert texts(doc, "#operator-toggle .join > button.btn.join-item[name=op]") == ["And", "Or"]
    assert texts(doc, "#operator-toggle .btn-primary[aria-pressed=true]") == ["And"]

    assert LazyHTML.attribute(LazyHTML.query(doc, "#tag-filter input[name=op]"), "value") == [
             "and"
           ]

    # Pressing Or sends the hidden op first, then the button's: the button's wins.
    html = conn |> get("/tags?op=and&tags[]=#{alpha.slug}&tags[]=#{beta.slug}&op=or")
    html = html_response(html, 200)
    assert titles(html) |> Enum.sort() == ["Alpha only", "Beta only", "Both tags"]
    assert html =~ "Topics carrying any of these tags"

    doc = LazyHTML.from_document(html)
    assert texts(doc, "#operator-toggle .btn-primary[aria-pressed=true]") == ["Or"]

    assert LazyHTML.attribute(LazyHTML.query(doc, "#tag-filter input[name=op]"), "value") == [
             "or"
           ]
  end

  @tag req: "TP-19"
  test "TP-19 topic lists show tags; a moderator edits them from the topic page", %{
    conn: conn,
    general: general,
    alpha: alpha,
    beta: beta
  } do
    topic = topic!(general, "Plans", [alpha])
    html = conn |> get(~p"/c/#{general.slug}") |> html_response(200)
    assert titles(html, "#topics .tag-chip") == [alpha.name]

    member_conn = log_in_user(build_conn(), user_fixture())

    refute member_conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200) =~
             "topic-tags-form"

    member_conn = post(member_conn, ~p"/t/#{topic.id}/tags", %{"tag_ids" => [beta.id]})
    assert Phoenix.Flash.get(member_conn.assigns.flash, :error) =~ "cannot change the tags"

    mod_conn = log_in_user(build_conn(), user_with_role_fixture(:moderator))

    assert mod_conn |> get(~p"/t/#{topic.id}/#{topic.slug}") |> html_response(200) =~
             "topic-tags-form"

    conn = post(mod_conn, ~p"/t/#{topic.id}/tags", %{"tag_ids" => [""]})
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Choose at least one tag."

    conn =
      post(mod_conn, ~p"/t/#{topic.id}/tags", %{
        "tag_ids" => ["", beta.id],
        "reason" => "Fits"
      })

    assert redirected_to(conn) == ~p"/t/#{topic.id}/#{topic.slug}"
    assert [%{id: id}] = Repo.preload(Repo.reload!(topic), :tags).tags
    assert id == beta.id
  end

  @tag req: "TP-19"
  test "TP-19 starting a topic asks for a tag of the category", %{
    general: general,
    alpha: alpha,
    beta: beta,
    secret: secret
  } do
    conn = log_in_user(build_conn(), user_fixture())
    {:ok, lv, html} = live(conn, ~p"/c/#{general.slug}/new")
    assert html =~ alpha.name
    assert html =~ beta.name
    refute html =~ secret.name

    html =
      lv
      |> form("#new-topic-form", topic: %{title: "Untagged", body: "Hi"})
      |> render_submit()

    assert html =~ "choose at least one tag"
    refute Repo.exists?(Idejo.Forum.Topic)

    {:ok, conn} =
      lv
      |> form("#new-topic-form", topic: %{title: "Tagged", body: "Hi", tag_ids: [beta.id]})
      |> render_submit()
      |> follow_redirect(conn)

    assert titles(html_response(conn, 200), ".topic-tags .tag-chip") == [beta.name]
  end

  @tag req: "TP-19"
  test "TP-19 administrators create, rename and delete tags in Admin → Tags", %{
    admin: admin,
    general: general,
    alpha: alpha
  } do
    conn = log_in_user(build_conn(), admin)
    {:ok, lv, html} = live(conn, ~p"/admin/tags")
    assert html =~ alpha.name

    name = "Gamma #{System.unique_integer([:positive])}"

    html =
      lv
      |> form("#new-tag-form", tag: %{name: name, category_id: general.id})
      |> render_submit()

    assert html =~ "Tag “#{name}” created."
    tag = Repo.get_by!(Idejo.Forum.Tag, name: name)
    assert tag.category_id == general.id

    lv |> element("#tag-#{tag.id} button", "Rename") |> render_click()

    assert lv
           |> form("#edit-tag-#{tag.id}", edit: %{name: name <> "!"})
           |> render_submit() =~ "saved."

    assert lv |> element("#tag-#{tag.id} button", "Delete") |> render_click() =~ "deleted."
    refute Repo.get(Idejo.Forum.Tag, tag.id)
  end

  @tag req: "TP-19"
  test "TP-19 tag pills read $, the sign of tags; # stays for topics" do
    css = File.read!("assets/css/app.css")
    [chip] = Regex.run(~r/\.tag-chip \{.*?\n  \}/s, css)
    assert chip =~ ~s(content: "$")
    refute chip =~ ~s(content: "#")
  end
end

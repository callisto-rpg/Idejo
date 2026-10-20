# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ImageUploadTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures

  alias Idejo.Forum
  alias Idejo.Messages.Body
  alias Idejo.Repo
  alias Idejo.Uploads
  alias Idejo.Uploads.Upload

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Pics", "body" => "Hi"})

    user = user_fixture()

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{conn: log_in_user(conn, user), user: user, topic: topic}
  end

  defp entry(name, path, type),
    do: %{name: name, content: File.read!(path), type: type, last_modified: 1_594_171_879_000}

  @tag req: "TP-12"
  test "TP-12 the new-topic editor has an Add image button that inserts the image's Markdown",
       %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/c/general/new")
    assert html =~ "Add image"
    assert has_element?(lv, "#topic_body-write[phx-hook=EditorImages][data-upload=editor_image]")

    input =
      file_input(lv, "#new-topic-form", :editor_image, [
        entry("Sunset [1].jpg", image_file(:jpg), "image/jpeg")
      ])

    render_upload(input, "Sunset [1].jpg")

    upload = Repo.one!(Upload)
    assert_push_event(lv, "image_uploaded", %{upload: :editor_image, markdown: markdown})
    assert markdown == "![Sunset 1](/uploads/#{upload.path})"
  end

  @tag req: "TP-12"
  test "TP-12 an image pasted into the composer uploads; the composer shows no button", %{
    conn: conn,
    topic: topic
  } do
    {:ok, lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    refute lv |> element("#composer") |> render() =~ "Add image"
    assert has_element?(lv, "#composer-image-form.hidden")

    input =
      file_input(lv, "#composer-image-form", :composer_image, [
        entry("cat.png", image_file(:png), "image/png")
      ])

    render_upload(input, "cat.png")

    upload = Repo.one!(Upload)
    assert_push_event(lv, "image_uploaded", %{upload: :composer_image, markdown: markdown})
    assert markdown == "![cat](/uploads/#{upload.path})"
    # Nothing is posted until the author sends it.
    assert length(Forum.list_messages(topic)) == 1
  end

  @tag req: "TP-12"
  test "TP-12 a file that is not an image is refused with a message", %{conn: conn, topic: topic} do
    {:ok, lv, _html} =
      live_isolated(conn, IdejoWeb.TopicLive, session: %{"topic_id" => topic.id})

    input =
      file_input(lv, "#composer-image-form", :composer_image, [
        entry("fake.png", raw_file("fake.png", "nope"), "image/png")
      ])

    render_upload(input, "fake.png")

    assert has_element?(lv, "[role=alert]", "Only JPEG, PNG, GIF and WebP images can be added.")
    assert Repo.aggregate(Upload, :count) == 0
  end

  @tag req: "TP-12"
  test "TP-12 uploaded images are served to anyone with the link, as images only", %{user: user} do
    {:ok, upload} = Uploads.store_image(user, image_file(:png))

    conn = get(build_conn(), "/uploads/#{upload.path}")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(conn, "set-cookie") == []

    assert get(build_conn(), "/uploads/#{Ecto.UUID.generate()}.png").status == 404
    assert get(build_conn(), "/uploads/..%2Fmix.exs").status == 404

    # And they show in messages: Markdown images are kept by the sanitiser.
    assert Body.to_html("![cat](/uploads/#{upload.path})") =~
             ~s(<img src="/uploads/#{upload.path}" alt="cat")
  end
end

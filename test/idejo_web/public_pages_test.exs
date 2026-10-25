# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PublicPagesTest do
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Forum

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture(%{display_name: "Ada"})

    {:ok, topic} =
      Forum.create_topic(member, general, %{"title" => "Garden plans", "body" => "Tomatoes"})

    long = Enum.map_join(1..80, "\n\n", &"Paragraph #{&1} about compost.")
    {:ok, reply} = Forum.post_message(member, topic, %{"body" => long})

    %{admin: admin, member: member, general: general, topic: topic, reply: reply}
  end

  # What a browser without JavaScript gets: the server's HTML, nothing more.
  defp page(conn, path), do: conn |> get(path) |> html_response(200)

  defp public_paths(%{general: general, topic: topic, member: member}) do
    [
      ~p"/",
      ~p"/c/#{general.slug}",
      ~p"/t/#{topic.id}/#{topic.slug}",
      ~p"/search?q=tomatoes",
      ~p"/u/#{member.id}"
    ]
  end

  defp signed_in_paths(%{general: general}) do
    [~p"/users/settings", ~p"/c/#{general.slug}/new", ~p"/admin"]
  end

  defp doc(html), do: LazyHTML.from_document(html)

  defp attributes(html, selector, attribute),
    do: html |> doc() |> LazyHTML.query(selector) |> LazyHTML.attribute(attribute)

  @tag req: "AX-04"
  test "AX-04 public pages carry their content in the HTML, readable without JavaScript",
       %{conn: conn, topic: topic, member: member} do
    assert page(conn, ~p"/") =~ "General"
    assert page(conn, ~p"/c/general") =~ "Garden plans"

    topic_page = page(conn, ~p"/t/#{topic.id}/#{topic.slug}")
    assert topic_page =~ "Garden plans"
    assert topic_page =~ "Tomatoes"
    assert topic_page =~ "Ada"
    # A long message is collapsed only by JavaScript: without it, all of it shows.
    assert topic_page =~ "Paragraph 80 about compost."
    assert attributes(topic_page, ".message-collapsible", "id") != []
    assert attributes(topic_page, ".message-collapsible[data-collapsed]", "id") == []

    assert page(conn, ~p"/search?q=tomatoes") =~ "Garden plans"
    assert page(conn, ~p"/u/#{member.id}") =~ "Ada"

    # The search boxes, the page's and the header's, are plain forms: they work without
    # scripts.
    assert attributes(page(conn, ~p"/search"), "form[action='/search']", "method") ==
             ["get", "get"]
  end

  @tag req: "CL-02"
  test "CL-02 the read view is server-rendered: plain links, one deferred script", %{
    conn: conn,
    topic: topic,
    reply: reply
  } do
    html = page(conn, ~p"/t/#{topic.id}/#{topic.slug}")

    # Each message is in the page, with a permalink that is a plain link.
    assert html =~ ~s(id="message-#{reply.id}")
    assert ~p"/m/#{reply.id}" in attributes(html, "a", "href")

    # Scripts only add to the page: the app's own bundle, deferred, and the theme switch.
    assert attributes(html, "script[src]", "src") == ["/assets/js/app.js", "/assets/js/theme.js"]
    assert attributes(html, "script[src='/assets/js/app.js']", "defer") == [""]
  end

  @tag req: "CL-01"
  test "CL-01 every page adapts to the screen width", %{conn: conn} = context do
    member_conn = log_in_user(build_conn(), context.admin)

    for {conn, path} <-
          Enum.map(public_paths(context), &{conn, &1}) ++
            Enum.map(signed_in_paths(context), &{member_conn, &1}) do
      viewport = attributes(page(conn, path), "meta[name='viewport']", "content")
      assert viewport == ["width=device-width, initial-scale=1"], path
    end
  end

  @tag req: "CL-01"
  test "CL-01 the site can be installed as a web app", %{conn: conn} = context do
    for path <- public_paths(context) do
      assert attributes(page(conn, path), "link[rel='manifest']", "href") ==
               ["/manifest.webmanifest"],
             path

      assert attributes(page(conn, path), "link[rel='apple-touch-icon']", "href") ==
               ["/images/icon-180.png"],
             path
    end

    conn = get(build_conn(), "/manifest.webmanifest")
    assert get_resp_header(conn, "content-type") == ["application/manifest+json; charset=utf-8"]
    assert get_resp_header(conn, "set-cookie") == []

    manifest = Jason.decode!(response(conn, 200))
    assert manifest["name"] == IdejoWeb.Layouts.server_name()
    assert manifest["start_url"] == "/"
    assert manifest["display"] == "standalone"

    for %{"src" => src, "sizes" => sizes} <-
          manifest["icons"] ++ [%{"src" => "/images/icon-180.png", "sizes" => "180x180"}] do
      {:ok, image} = Image.from_binary(response(get(build_conn(), src), 200))
      assert "#{Image.width(image)}x#{Image.height(image)}" == sizes, src
    end
  end

  @tag req: "SP-04"
  test "SP-04 pages load scripts, styles, fonts and images from the server only", context do
    member_conn = log_in_user(build_conn(), context.admin)

    for {conn, path} <-
          Enum.map(public_paths(context), &{context.conn, &1}) ++
            Enum.map(signed_in_paths(context), &{member_conn, &1}) do
      html = page(conn, path)

      loaded =
        attributes(html, "script[src], img[src], iframe[src], audio[src], video[src]", "src") ++
          attributes(
            html,
            "link[rel='stylesheet'], link[rel~='icon'], link[rel='preload']",
            "href"
          )

      for url <- loaded do
        assert String.starts_with?(url, "/") and not String.starts_with?(url, "//"),
               "#{path} loads #{url} from elsewhere"
      end
    end
  end

  @tag req: "SP-04"
  test "SP-04 the app's own scripts and styles reach no other site" do
    sources = Path.wildcard("assets/{js,css,vendor}/**/*.{js,css}")
    assert sources != []

    for file <- sources do
      code =
        file
        |> File.read!()
        # Links in comments are documentation, not requests.
        |> String.replace(~r{/\*.*?\*/}s, "")
        |> String.replace(~r{(^|\s)//[^\n]*}, "")

      refute code =~ ~r{https?://}, "#{file} names another site"
      refute code =~ ~r{@import\s+url}, "#{file} imports a stylesheet"
    end
  end
end

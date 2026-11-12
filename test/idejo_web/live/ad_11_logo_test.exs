# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AD11LogoTest do
  @moduledoc """
  AD-11: administrators replace the header's small Idejo logo with the forum's own, in
  Admin → Settings. Not async: the logo is a setting every page reads.
  """
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query
  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures
  import Phoenix.LiveViewTest

  alias Idejo.Audit.Entry
  alias Idejo.{Repo, Settings, Uploads}
  alias Idejo.Settings.Logo

  @moduletag req: "AD-11"

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp choose(lv, path, name \\ "logo.png") do
    lv
    |> file_input("#logo-form", :logo, [
      %{name: name, content: File.read!(path), type: "image/png"}
    ])
    |> render_upload(name)
  end

  defp header_logo(conn) do
    conn
    |> get(~p"/")
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("#brand > img.brand-mark")
    |> LazyHTML.attribute("src")
  end

  test "AD-11 an administrator uploads the forum's logo and every page's header shows it", %{
    conn: conn
  } do
    assert header_logo(build_conn()) == ["/images/logo-small.svg"]

    {:ok, lv, _html} = live(conn, ~p"/admin")
    refute has_element?(lv, "#remove-logo")

    assert {:error, {:redirect, %{to: "/admin"}}} =
             choose(lv, image_file(:png, width: 600, height: 100))

    url = Settings.get(:brand_logo)
    assert url =~ ~r"\A/uploads/[0-9a-f-]{36}\.webp\z"
    assert header_logo(build_conn()) == [url]

    # Fitted whole inside 256 px: a wide logo keeps its shape.
    {_upload, file} = Uploads.get_by_name(Path.basename(url))
    {:ok, image} = Image.open(file)
    assert {Image.width(image), Image.height(image)} == {256, 43}

    assert %Entry{before: %{"brand_logo" => ""}, after: %{"brand_logo" => ^url}} =
             Repo.one(
               from e in Entry,
                 where: e.change == "settings.update",
                 order_by: [desc: e.id],
                 limit: 1
             )

    {:ok, lv, html} = live(conn, ~p"/admin")
    assert html =~ ~s(src="#{url}")
    assert has_element?(lv, "#remove-logo")
  end

  test "AD-11 \"Use the Idejo logo\" goes back, and a replaced logo's file is deleted", %{
    conn: conn,
    admin: admin
  } do
    {:ok, first} = Logo.set(admin, image_file(:png))
    {:ok, second} = Logo.set(admin, image_file(:jpg))
    refute first == second
    assert Uploads.get_by_name(Path.basename(first)) == nil

    {:ok, lv, _html} = live(conn, ~p"/admin")

    assert {:error, {:redirect, %{to: "/admin"}}} =
             lv |> element("#remove-logo") |> render_click()

    assert Settings.get(:brand_logo) == ""
    assert Uploads.get_by_name(Path.basename(second)) == nil
    assert header_logo(build_conn()) == ["/images/logo-small.svg"]
  end

  test "AD-11 a file that is not an image is refused and the logo stays", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin")
    html = choose(lv, raw_file("logo.png", "not an image"))

    assert html =~ "role=\"alert\""
    assert Settings.get(:brand_logo) == ""
  end

  test "AD-11 the setting only ever names an uploaded logo, which the cleanup keeps", %{
    admin: admin
  } do
    assert {:error, changeset} =
             Settings.update_settings(admin, %{brand_logo: "https://x.test/a.png"})

    assert changeset.errors[:brand_logo]

    {:ok, url} = Logo.set(admin, image_file(:png))
    Uploads.delete_unused(DateTime.add(DateTime.utc_now(), 1, :day))
    assert Uploads.get_by_name(Path.basename(url))
  end

  @tag req: "AD-11"
  test "AD-11 the forum's logo has a fixed public address, /logo, for directories", %{
    admin: admin
  } do
    conn = get(build_conn(), ~p"/logo")
    assert redirected_to(conn, 302) == "/images/logo-small.svg"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    # No session: nothing set, nothing personal.
    assert get_resp_header(conn, "set-cookie") == []

    {:ok, url} = Logo.set(admin, image_file(:png))
    assert redirected_to(get(build_conn(), ~p"/logo"), 302) == url
    assert get(build_conn(), url).status == 200
  end

  @tag req: "AD-11"
  test "AD-11 the favicon is the forum's logo once it has one, else Idejo's", %{admin: admin} do
    icons = fn ->
      build_conn()
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s(link[rel="icon"]))
      |> Enum.map(&{LazyHTML.attribute(&1, "type"), LazyHTML.attribute(&1, "href")})
    end

    assert icons.() == [{["image/png"], ["/images/favicon.png"]}]

    {:ok, url} = Logo.set(admin, image_file(:png))
    assert icons.() == [{["image/webp"], [url]}]

    {:ok, _} = Logo.remove(admin)
    assert icons.() == [{["image/png"], ["/images/favicon.png"]}]
  end
end

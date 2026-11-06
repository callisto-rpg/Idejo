# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AD11StylesheetTest do
  @moduledoc """
  AD-11: the server's stylesheet (Admin → Stylesheet) loads nothing from elsewhere and runs
  nothing; it is checked before it is saved (SP-04).
  """
  # Writes the server-wide stylesheet setting, which every test shares.
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Idejo.Settings
  alias Idejo.Settings.Stylesheet

  @moduletag req: "AD-11"

  test "AD-11 styles, local addresses and data: images and fonts are fine" do
    for css <- [
          Settings.default(:custom_css),
          ".a { color: red; background: url(/uploads/0193.webp) }",
          ".a { background: url('images/bg.png') }",
          ~s|.a { background-image: image-set("/images/a.png" 1x, "/images/a@2x.png" 2x) }|,
          "@font-face { font-family: X; src: url(data:font/woff2;base64,AAAA) }",
          ~s|.a::after { content: "see https://example.org" }|,
          ".a { behavior-like-name: 1 }"
        ] do
      assert Stylesheet.check(css) == :ok, css
    end
  end

  test "AD-11 nothing from another site, however it is written" do
    for css <- [
          ".a { background: url(https://evil.test/x.png) }",
          ".a { background: url( \"//evil.test/x.png\" ) }",
          ".a { background: URL(HTTP://evil.test/x.png) }",
          # CSS escapes spell the same thing: u\72l( is url(, and \68ttps is https.
          ".a { background: u\\72l(\\68ttps://evil.test/x.png) }",
          ~s|.a { background-image: -webkit-image-set("https://evil.test/a.png" 1x) }|,
          "@font-face { src: url(ftp://evil.test/f.woff) }"
        ] do
      assert {:error, reason} = Stylesheet.check(css), css
      assert reason =~ "addresses on this server", css
    end

    assert {:error, "must not use @import" <> _} = Stylesheet.check("@import 'x.css';")
    # A comment after the keyword hides nothing (one inside it splits it: not an @import).
    assert {:error, "must not use @import" <> _} = Stylesheet.check("@import/* x */url(/a.css);")
    assert {:error, "must not use @import" <> _} = Stylesheet.check("@\\69mport url(/a.css);")
  end

  test "AD-11 nothing that ever ran script" do
    for css <- [
          ".a { width: expression(alert(1)) }",
          ".a { behavior: url(/x.htc) }",
          ".a { -moz-binding: url(/x.xml#b) }",
          ".a { background: url(javascript:alert(1)) }",
          ".a { background: url(vbscript:x) }"
        ] do
      assert {:error, _} = Stylesheet.check(css), css
    end

    assert {:error, ~s|must not contain "</"|} =
             Stylesheet.check("</style><script>alert(1)</script>")
  end

  test "AD-11 Admin → Stylesheet refuses it, says why and keeps the text" do
    admin = user_with_role_fixture(:administrator)
    before = Settings.get(:custom_css)
    {:ok, view, _} = live(log_in_user(build_conn(), admin), ~p"/admin/stylesheet")
    css = ".a { background: url(https://evil.test/x.png) }"

    html = view |> form("#stylesheet-form", theme: %{custom_css: css}) |> render_submit()
    assert html =~ "Not saved: the stylesheet may only use addresses on this server"
    assert html =~ "evil.test"
    assert Settings.get(:custom_css) == before

    assert {:error, changeset} = Settings.update_settings(admin, %{custom_css: "@import 'x';"})
    assert {"must not use @import" <> _, _} = changeset.errors[:custom_css]
  end
end

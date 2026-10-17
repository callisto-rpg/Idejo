# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Plugs.ContentSecurityPolicyTest do
  use IdejoWeb.ConnCase, async: true

  @tag req: "SP-05"
  test "SP-05 browser pages send a content security policy that only allows the app itself",
       %{conn: conn} do
    conn = get(conn, ~p"/")
    [policy] = get_resp_header(conn, "content-security-policy")

    assert policy =~ "default-src 'self'"
    assert policy =~ "object-src 'none'"
    assert policy =~ "frame-ancestors 'none'"
    assert policy =~ "script-src 'self' 'nonce-#{conn.assigns.script_csp_nonce}'"
    assert policy =~ "style-src 'self' 'nonce-#{conn.assigns.style_csp_nonce}'"
    refute policy =~ "unsafe-inline"
    refute policy =~ "unsafe-eval"
  end

  @tag req: "SP-05"
  test "SP-05 each response gets a fresh nonce", %{conn: conn} do
    first = get(conn, ~p"/").assigns.script_csp_nonce
    second = get(build_conn(), ~p"/").assigns.script_csp_nonce

    assert byte_size(first) >= 22
    refute first == second
  end

  @tag req: "SP-05"
  test "SP-05 pages carry no inline scripts", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    for script <- Regex.scan(~r/<script\b[^>]*>/, html) do
      assert hd(script) =~ "src="
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SP10CookiesTest do
  @moduledoc """
  SP-10: every cookie the app sets is host-only (no `Domain` attribute), so a session on one
  host is never sent to another host of the same domain (several forums on one host, v1 §13).
  """
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures
  import Phoenix.LiveViewTest

  # Every cookie the server sets. A new one must be added here, after checking it too.
  @known ["_idejo_key", "_idejo_web_user_remember_me"]

  defp set_cookies(conn), do: Plug.Conn.get_resp_header(conn, "set-cookie")

  defp name(set_cookie), do: set_cookie |> String.split("=", parts: 2) |> hd()

  defp attributes(set_cookie) do
    set_cookie
    |> String.split(";")
    |> tl()
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
  end

  defp sign_in(conn, user) do
    post(conn, ~p"/users/sign-in", %{
      "user" => %{
        "email" => user.email,
        "password" => valid_user_password(),
        "remember_me" => "true"
      }
    })
  end

  @tag req: "SP-10"
  test "SP-10 no cookie the app sets carries a Domain attribute" do
    user = user_fixture(%{welcome: true})
    headers = []

    # A visitor: the guest card's form writes the session.
    conn = post(build_conn(), ~p"/continue-as-guest")
    headers = headers ++ set_cookies(conn)

    # Sign-in with remember me: the session and the remember-me cookie.
    signed_in = sign_in(build_conn(), user)
    headers = headers ++ set_cookies(signed_in)
    assert Enum.any?(headers, &(name(&1) == "_idejo_web_user_remember_me"))

    # A new browser session from the remember-me cookie alone.
    remembered =
      build_conn()
      |> put_req_cookie(
        "_idejo_web_user_remember_me",
        signed_in.resp_cookies["_idejo_web_user_remember_me"].value
      )
      |> get(~p"/")

    headers = headers ++ set_cookies(remembered)

    # A LiveView page, its live connection, and the welcome card's form (a sent conn is
    # recycled with its cookies, as a browser would).
    page = get(signed_in, ~p"/users/settings")
    headers = headers ++ set_cookies(page)
    {:ok, _view, _html} = live(signed_in, ~p"/users/settings")

    welcome = post(signed_in, ~p"/welcome", %{})
    headers = headers ++ set_cookies(welcome)

    # Sign-out deletes the remember-me cookie and renews the session.
    signed_out = delete(signed_in, ~p"/users/sign-out")
    headers = headers ++ set_cookies(signed_out)

    assert Enum.any?(set_cookies(signed_out), &(name(&1) == "_idejo_web_user_remember_me"))

    names = headers |> Enum.map(&name/1) |> Enum.uniq() |> Enum.sort()
    assert names == @known, "cookies set: #{inspect(names)}"

    for header <- headers do
      attributes = attributes(header)
      refute Enum.any?(attributes, &String.starts_with?(&1, "domain")), header
      assert "path=/" in attributes, header
      # SP-02: never readable by scripts, never sent over plain http, never cross-site posts.
      assert "httponly" in attributes, header
      assert "secure" in attributes, header
      assert "samesite=lax" in attributes, header
    end
  end

  @tag req: "SP-10"
  test "SP-10 no code or configuration gives a cookie a domain" do
    # Elixir: every place that sets or deletes a cookie, or configures the session.
    cookie_code =
      for path <- Path.wildcard("lib/**/*.ex"),
          source = File.read!(path),
          source =~ ~r/put_resp_cookie|delete_resp_cookie|Plug\.Session|store: :cookie/,
          do: {path, source}

    assert Enum.map(cookie_code, &elem(&1, 0)) |> Enum.sort() ==
             ["lib/idejo_web/endpoint.ex", "lib/idejo_web/user_auth.ex"],
           "a new place sets cookies: check it is host-only, then add it here"

    for {path, source} <- cookie_code do
      refute source =~ ~r/\bdomain:/, "#{path} gives a cookie a domain"
    end

    # Configuration: no session or cookie option with a domain (comments aside).
    for path <- Path.wildcard("config/*.exs") do
      code =
        path
        |> File.read!()
        |> String.split("\n")
        |> Enum.reject(&(String.trim_leading(&1) |> String.starts_with?("#")))
        |> Enum.join("\n")

      refute code =~ ~r/\bdomain:/, "#{path} sets a domain"
      refute code =~ ~r/session_options|cookie_domain/, "#{path} configures cookies"
    end

    # Scripts: LiveView's flash cookie is set by its own script with `path=/` only; ours
    # set none.
    for path <- Path.wildcard("assets/js/**/*.js") do
      refute File.read!(path) =~ ~r/document\.cookie/, "#{path} sets a cookie"
    end

    assert File.read!("deps/phoenix_live_view/assets/js/phoenix_live_view/browser.ts") =~
             "document.cookie = `${name}=${value};${expires} path=/`;"
  end
end

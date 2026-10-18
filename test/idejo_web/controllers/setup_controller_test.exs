# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.SetupControllerTest do
  # Turns the setup redirect on, so not async.
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Settings
  alias Idejo.Setup

  setup do
    Application.put_env(:idejo, :setup_redirect, true)
    on_exit(fn -> Application.put_env(:idejo, :setup_redirect, false) end)
  end

  defp params(overrides \\ %{}) do
    Map.merge(
      %{
        "code" => Setup.token(),
        "owner" => %{
          "email" => "owner@example.org",
          "username" => "owner",
          "display_name" => "Olga Owner",
          "password" => valid_user_password()
        },
        "settings" => %{
          "server_name" => "Lumière",
          "mail_from" => "forum@example.org",
          "smtp_host" => "",
          "smtp_port" => "587",
          "smtp_security" => "starttls"
        }
      },
      overrides
    )
  end

  @tag req: "AD-01"
  test "AD-01 until set up, every page leads to the wizard", %{conn: conn} do
    for path <- [~p"/", ~p"/users/sign-in", ~p"/users/sign-up", ~p"/admin"] do
      assert redirected_to(get(conn, path)) == ~p"/setup"
    end
  end

  @tag req: "AD-01"
  test "AD-01 the wizard asks for the code, server name, owner and email", %{conn: conn} do
    html = conn |> get(~p"/setup?code=abc") |> html_response(200)

    assert html =~ "Set up your server"
    assert html =~ ~s(name="setup[code]")
    assert html =~ ~s(value="abc")
    assert html =~ ~s(name="setup[settings][server_name]")
    assert html =~ ~s(name="setup[owner][email]")
    assert html =~ ~s(name="setup[owner][password]")
    assert html =~ ~s(name="setup[settings][smtp_host]")
    assert html =~ "Idejo is not set up yet"
    # A plain form: it works without JavaScript.
    assert html =~ ~s(action="/setup")
    assert html =~ ~s(method="post")
  end

  @tag req: "AD-01"
  test "AD-01 completing the wizard signs the owner in and opens the email settings", %{
    conn: conn
  } do
    conn = post(conn, ~p"/setup", %{"setup" => params()})

    assert redirected_to(conn) == ~p"/admin/email"
    assert get_session(conn, :user_token)
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "The server is set up"
    assert Settings.get(:server_name) == "Lumière"

    conn = get(recycle(conn), ~p"/admin/email")
    assert html_response(conn, 200) =~ "SMTP host"
  end

  @tag req: "AD-01"
  test "AD-01 a wrong code keeps the wizard and creates nothing", %{conn: conn} do
    conn = post(conn, ~p"/setup", %{"setup" => params(%{"code" => "guess"})})

    html = html_response(conn, 200)
    assert html =~ "The setup code is wrong"
    assert html =~ "olga" or html =~ "owner@example.org"
    refute html =~ valid_user_password()
    assert Setup.needed?()
  end

  @tag req: "AD-01"
  test "AD-01 field errors are shown and nothing is created", %{conn: conn} do
    bad =
      params(%{
        "owner" => %{"email" => "bad", "username" => "", "display_name" => "", "password" => "x"}
      })

    html = conn |> post(~p"/setup", %{"setup" => bad}) |> html_response(200)

    assert html =~ "must have the @ sign and no spaces"
    assert html =~ ~s(value="#{Setup.token()}")
    assert Setup.needed?()
  end

  @tag req: "AD-01"
  test "AD-01 after setup the wizard is gone and pages open normally", %{conn: conn} do
    user_with_role_fixture(:owner)

    assert redirected_to(get(conn, ~p"/setup")) == ~p"/"
    assert redirected_to(post(conn, ~p"/setup", %{"setup" => params()})) == ~p"/"
    assert html_response(get(conn, ~p"/users/sign-in"), 200) =~ "Sign in"
  end
end

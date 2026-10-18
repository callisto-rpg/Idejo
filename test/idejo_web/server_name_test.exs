# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ServerNameTest do
  @moduledoc """
  The header and page titles show the server name set in the admin panel, or "Idejo".
  """
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Settings

  defp header(html), do: html |> LazyHTML.from_document() |> LazyHTML.query("header a")
  defp title(html), do: html |> LazyHTML.from_document() |> LazyHTML.query("title")

  @tag req: "AD-02"
  test "AD-02 without a server name, header and title say Idejo", %{conn: conn} do
    html = conn |> get(~p"/users/sign-in") |> html_response(200)

    assert LazyHTML.text(header(html)) =~ "Idejo"
    assert LazyHTML.text(title(html)) == "Sign in · Idejo"
  end

  @tag req: "AD-02"
  test "AD-02 the header and title show the server name", %{conn: conn} do
    {:ok, _} = Settings.update_settings(user_fixture(), %{"server_name" => "Lumière"})

    html = conn |> get(~p"/users/sign-in") |> html_response(200)
    assert LazyHTML.text(header(html)) =~ "Lumière"
    assert LazyHTML.text(title(html)) == "Sign in · Lumière"
    refute html =~ "Phoenix"

    # Signed-in LiveView pages too.
    admin = user_with_role_fixture(:administrator)
    {:ok, _lv, html} = conn |> log_in_user(admin) |> live(~p"/admin")
    assert html =~ "Lumière"
  end

  @tag req: "AD-02"
  test "AD-02 a page without its own title shows the server name alone", %{conn: conn} do
    {:ok, _} = Settings.update_settings(user_fixture(), %{"server_name" => "Lumière"})

    html = conn |> get(~p"/") |> html_response(200)
    assert LazyHTML.text(title(html)) == "Lumière"
  end
end

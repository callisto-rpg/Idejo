# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.OIDCSignUpLinkTest do
  @moduledoc """
  AC-09 (steward decision, 2026-11-06): with IDEJO_OIDC_SIGN_UP_URL, people without an account
  at the provider find where to make one, under its button on sign-in and sign-up.
  """
  use IdejoWeb.ConnCase, async: false

  alias IdejoWeb.Accessibility

  @url "https://id.example.test/account/sign-up?return_to=https%3A%2F%2Fclub.example.test%2F"

  setup do
    oidc = Application.get_env(:idejo, :oidc)
    url = Application.get_env(:idejo, :oidc_sign_up_url)

    on_exit(fn ->
      if oidc,
        do: Application.put_env(:idejo, :oidc, oidc),
        else: Application.delete_env(:idejo, :oidc)

      Application.put_env(:idejo, :oidc_sign_up_url, url)
    end)

    Application.put_env(:idejo, :oidc,
      issuer: "https://id.example.test",
      client_id: "c",
      client_secret: "s",
      label: "Example ID"
    )

    :ok
  end

  @tag req: "AC-09"
  test "AC-09 sign-in and sign-up say where to make an account at the provider", %{conn: conn} do
    Application.put_env(:idejo, :oidc_sign_up_url, @url)

    for {path, id} <- [
          {~p"/users/sign-in", "oidc-sign-in-create"},
          {~p"/users/sign-up", "oidc-sign-up-create"}
        ] do
      html = conn |> get(path) |> html_response(200)
      link = html |> LazyHTML.from_document() |> LazyHTML.query("##{id} a")
      assert LazyHTML.attribute(link, "href") == [@url], path

      assert html |> LazyHTML.from_document() |> LazyHTML.query("##{id}") |> LazyHTML.text() =~
               "No Example ID yet?"

      assert Accessibility.audit(html) == [], path
    end
  end

  @tag req: "AC-09"
  test "AC-09 without the address, or without the provider, no such link", %{conn: conn} do
    Application.put_env(:idejo, :oidc_sign_up_url, nil)
    refute conn |> get(~p"/users/sign-in") |> html_response(200) =~ "oidc-sign-in-create"

    Application.put_env(:idejo, :oidc_sign_up_url, @url)
    Application.delete_env(:idejo, :oidc)
    refute build_conn() |> get(~p"/users/sign-in") |> html_response(200) =~ "oidc-sign-in-create"
  end
end

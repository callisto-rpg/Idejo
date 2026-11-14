# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AP20SwitchTest do
  @moduledoc """
  AP-20: "API and mobile app" in Admin → Settings, on by default. Off, everything of the
  API answers 404 and live sockets close; tokens are kept and work again once it is on.
  AP-18: limits per token and pages.
  """
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures
  import IdejoWeb.ApiHelpers
  import Phoenix.LiveViewTest

  alias Idejo.Settings
  alias IdejoWeb.Api.{Controller, Revocations}

  setup do
    admin = user_with_role_fixture(:administrator)
    user = user_fixture()
    {token, row} = api_token_fixture(user)
    %{admin: admin, user: user, token: token, row: row}
  end

  defp switch(admin, on?),
    do: {:ok, _} = Settings.update_settings(admin, %{"api_enabled" => to_string(on?)})

  @tag req: "AP-20"
  test "AP-20 on by default, and in Admin → Settings under its heading", %{
    conn: conn,
    admin: admin
  } do
    assert Settings.get(:api_enabled) == true
    {:ok, _lv, html} = conn |> log_in_user(admin) |> live(~p"/admin")
    assert html =~ "API and mobile app"
    assert html =~ ~s(name="settings[api_enabled]")
  end

  @tag req: "AP-20"
  test "AP-20 off: the API, the authorize page and the socket answer 404; tokens kept", %{
    conn: conn,
    admin: admin,
    user: user,
    token: token
  } do
    switch(admin, false)

    for path <- ["/api/v1/me", "/api/v1/openapi.json", "/api/v1/categories"] do
      body = build_conn() |> api_conn(token) |> get(path) |> api_json(404)
      assert body["error"]["code"] == "not_found"
    end

    {_verifier, challenge} = pkce()
    page = conn |> log_in_user(user) |> get(~p"/app/authorize?#{authorize_params(challenge)}")
    assert page.status == 404

    assert {:error, :disabled} =
             connect_app(token)

    assert get(build_conn(), ~p"/.well-known/idejo") |> json_response(200) |> Map.take(["api"]) ==
             %{"api" => nil}

    switch(admin, true)
    assert build_conn() |> api_conn(token) |> get(~p"/api/v1/me") |> api_json(200)
  end

  @tag req: "AP-20"
  test "AP-20 turning it off closes the sockets that are open", %{admin: admin, row: row} do
    IdejoWeb.Endpoint.subscribe(Revocations.socket_id(row.id))
    switch(admin, false)
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}, 1_000
    switch(admin, true)
  end

  @tag req: "AP-18"
  test "AP-18 every token has an overall limit per minute", %{token: token} do
    Application.put_env(:idejo, :rate_limits, enabled: true)
    Application.put_env(:idejo, :api_token_requests_per_minute, 3)

    on_exit(fn ->
      Application.put_env(:idejo, :rate_limits, enabled: false)
      Application.delete_env(:idejo, :api_token_requests_per_minute)
    end)

    for _ <- 1..3, do: build_conn() |> api_conn(token) |> get(~p"/api/v1/me") |> api_json(200)
    limited = build_conn() |> api_conn(token) |> get(~p"/api/v1/me")
    assert api_json(limited, 429)["error"]["code"] == "rate_limited"
    assert get_resp_header(limited, "retry-after") == ["60"]
  end

  @tag req: "AP-18"
  test "AP-18 pages: 50 by default, 100 at most, opaque signed cursors", %{
    admin: admin,
    token: token
  } do
    {:ok, category} = Idejo.Forum.create_category(admin, %{"name" => "Busy"})

    for i <- 1..3,
        do: Idejo.Forum.create_topic(admin, category, %{"title" => "T#{i}", "body" => "x"})

    page =
      build_conn()
      |> api_conn(token)
      |> get(~p"/api/v1/categories/#{category.id}/topics?limit=2")
      |> api_json(200)

    assert length(page["data"]) == 2
    assert page["prev_cursor"] == nil

    next =
      build_conn()
      |> api_conn(token)
      |> get(~p"/api/v1/categories/#{category.id}/topics?limit=2&cursor=#{page["next_cursor"]}")
      |> api_json(200)

    assert length(next["data"]) == 1
    assert next["prev_cursor"]

    bad =
      build_conn()
      |> api_conn(token)
      |> get(~p"/api/v1/categories/#{category.id}/topics?cursor=forged")

    assert api_json(bad, 400)["error"]["code"] == "bad_request"
    assert Controller.limit(%{"limit" => "1000"}) == 100
    assert Controller.limit(%{}) == 50
  end
end

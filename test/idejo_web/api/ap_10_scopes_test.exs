# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AP10ScopesTest do
  @moduledoc """
  AP-10, AP-17: generated from `IdejoWeb.Api.Operations`, so a new endpoint cannot skip
  them. Every operation that needs a token refuses none, a revoked one and one without its
  scope; every operation taking the id of something a user may not see answers 404, the
  same as for an id that does not exist.
  """
  use IdejoWeb.ConnCase, async: true

  import Idejo.AccountsFixtures
  import IdejoWeb.ApiHelpers

  alias Idejo.Accounts.ApiTokens
  alias IdejoWeb.Api.Operations

  @guarded Enum.filter(Operations.all(), & &1.scope)

  defp op_path(op, ids \\ %{}) do
    Regex.replace(~r/\{(\w+)\}/, op.path, fn _, name ->
      Map.get(ids, name) ||
        Map.get(
          %{"emoji" => "agree", "command" => "youtube", "name" => "rules"},
          name,
          Ecto.UUID.generate()
        )
    end)
  end

  defp call(conn, op, path, body \\ %{}) do
    Phoenix.ConnTest.dispatch(conn, @endpoint, op.method, "/api/v1" <> path, body)
  end

  @tag req: "AP-10"
  test "AP-10 every operation that needs a token refuses none and a revoked one", %{conn: conn} do
    user = user_fixture()
    {revoked, _row} = api_token_fixture(user)
    :ok = ApiTokens.revoke_by_token(revoked)

    for op <- @guarded do
      body = conn |> call(op, op_path(op)) |> api_json(401)
      assert body["error"]["code"] == "unauthenticated", "#{op.method} #{op.path} without a token"

      body = build_conn() |> api_conn(revoked) |> call(op, op_path(op)) |> api_json(401)

      assert body["error"]["code"] == "invalid_token",
             "#{op.method} #{op.path} with a revoked token"
    end
  end

  @tag req: "AP-10"
  test "AP-10 every operation refuses a token without its scope" do
    user = user_fixture()

    tokens =
      Map.new(ApiTokens.scopes(), fn scope ->
        {token, _row} = api_token_fixture(user, ApiTokens.scopes() -- [scope])
        {scope, token}
      end)

    for op <- @guarded do
      body = build_conn() |> api_conn(tokens[op.scope]) |> call(op, op_path(op)) |> api_json(403)

      assert body["error"]["code"] == "insufficient_scope",
             "#{op.method} #{op.path} without #{op.scope}"
    end
  end

  @tag req: "AP-10"
  test "AP-10 a private conversation also needs the private scope where reached by id" do
    world = IdejoWeb.ApiWorld.build()
    {token, _row} = api_token_fixture(world.other, ApiTokens.scopes() -- ["private"])
    conversation = world.conversation

    for url <- ["/api/v1/topics/#{conversation.id}", "/api/v1/topics/#{conversation.id}/composer"] do
      body = build_conn() |> api_conn(token) |> get(url) |> api_json(403)
      assert body["error"]["code"] == "insufficient_scope"
    end
  end

  # Path segment => what of the world stands for it, hidden from a plain member.
  defp hidden_ids(world) do
    %{
      "categories" => world.hidden.id,
      "topics" => world.secret.id,
      "messages" => world.secret_message.id,
      "conversations" => world.conversation.id,
      "polls" => world.secret_poll,
      "moderation/messages" => world.secret_message.id,
      "moderation/reports" => world.secret_message.id
    }
  end

  defp kind(%{path: "/moderation/messages/{id}" <> _}), do: "moderation/messages"
  defp kind(%{path: "/moderation/reports/{id}" <> _}), do: "moderation/reports"
  defp kind(%{path: "/" <> rest}), do: rest |> String.split("/") |> hd()

  @tag req: "AP-17"
  test "AP-17 an id the user may not see answers 404, like one that does not exist" do
    world = IdejoWeb.ApiWorld.build()
    {token, _row} = api_token_fixture(world.member)
    hidden = hidden_ids(world)

    for op <- @guarded, String.contains?(op.path, "{id}"), id = hidden[kind(op)] do
      for id <- [id, Ecto.UUID.generate()] do
        conn =
          build_conn()
          |> api_conn(token)
          |> call(op, op_path(op, %{"id" => id}), %{"message_id" => id, "category_id" => id})

        assert conn.status == 404,
               "#{op.method} #{op.path} gave #{conn.status}: #{conn.resp_body}"

        body = api_json(conn, 404)
        assert body["error"]["code"] == "not_found", "#{op.method} #{op.path} gave #{conn.status}"
      end
    end
  end

  @tag req: "AP-17"
  test "AP-17 errors have one shape with a stable code and the web's words" do
    body = build_conn() |> get(~p"/api/v1/nowhere") |> api_json(404)

    assert body == %{
             "error" => %{
               "code" => "not_found",
               "message" => body["error"]["message"],
               "details" => %{}
             }
           }

    body = build_conn() |> get(~p"/api/v2/anything") |> api_json(404)
    assert body["error"]["code"] == "not_found"
  end
end

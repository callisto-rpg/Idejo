# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.ContractTest do
  @moduledoc """
  AP-01, AP-17: the OpenAPI document and the router agree, and every error code the API
  answers is documented with its status and words. Each response of the API tests is also
  checked against its schema by `IdejoWeb.ApiHelpers.api_json/2`, and an undocumented
  error code raises (`config :idejo, :api_strict_errors`).
  """
  use IdejoWeb.ConnCase, async: true

  alias IdejoWeb.Api.{Errors, OpenApi}

  defp routed do
    for %{path: "/api/v1/" <> _ = path, verb: verb} <- IdejoWeb.Router.__routes__(),
        verb != :*,
        into: MapSet.new() do
      {verb,
       path
       |> String.replace_prefix("/api/v1", "")
       |> then(&Regex.replace(~r/:(\w+)/, &1, "{\\1}"))}
    end
  end

  defp documented do
    for {path, methods} <- OpenApi.document()["paths"],
        {method, _op} <- methods,
        into: MapSet.new() do
      {String.to_atom(method), path}
    end
  end

  @tag req: "AP-01"
  test "AP-01 every API route is documented and every documented path is routed" do
    assert MapSet.difference(routed(), documented()) |> MapSet.to_list() == []
    assert MapSet.difference(documented(), routed()) |> MapSet.to_list() == []
  end

  @tag req: "AP-01"
  test "AP-01 the document is served, OpenAPI 3.1, with Bearer, scopes and the events", %{
    conn: conn
  } do
    body = conn |> get(~p"/api/v1/openapi.json") |> json_response(200)
    assert body["openapi"] == "3.1.0"
    assert body["components"]["securitySchemes"]["bearer"]["scheme"] == "bearer"
    assert body["x-idejo-events"]["channels"]["topic:<id>"]["events"]["message.appended"]

    for {_path, methods} <- body["paths"], {_method, op} <- methods do
      assert op["summary"] && op["responses"]
      assert Map.has_key?(op, "x-idejo-scope")
    end

    refs =
      Regex.scan(~r{"#/components/schemas/(\w+)"}, Jason.encode!(body["paths"]),
        capture: :all_but_first
      )
      |> List.flatten()
      |> Enum.uniq()

    assert refs -- Map.keys(body["components"]["schemas"]) == []
  end

  @tag req: "AP-17"
  test "AP-17 every error code has a status and words, and is in the document" do
    documented = OpenApi.document()["x-idejo-error-codes"]

    for {code, status} <- Errors.codes() do
      assert status in [400, 401, 403, 404, 409, 410, 413, 422, 429, 500]
      assert is_binary(Errors.message(code)) and Errors.message(code) != ""
      assert documented[Atom.to_string(code)]["status"] == status
    end
  end
end

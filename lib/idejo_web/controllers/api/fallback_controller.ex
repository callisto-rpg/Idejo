# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.FallbackController do
  @moduledoc """
  Turns what an API action returned on failure into the error shape (AP-17,
  `IdejoWeb.Api.Errors`): `{:error, code}`, `{:error, code, details}`, a tagged refusal
  such as `{:error, {:cooldown, until}}`, or a changeset (422 `validation`, with
  `details.fields`). Also the 404 of any path under `/api` that is not a route.
  """
  use Phoenix.Controller, formats: [:json]

  alias IdejoWeb.Api.Errors

  @doc false
  def call(conn, {:error, %Ecto.Changeset{} = changeset}),
    do: Errors.send_error(conn, :validation, %{"fields" => fields(changeset)})

  def call(conn, {:error, {:cooldown, until}}),
    do: Errors.send_error(conn, :cooldown, %{"until" => DateTime.to_iso8601(until)})

  def call(conn, {:error, :rate_limited}),
    do: Errors.send_error(conn, :rate_limited, %{"retry_after" => 60})

  def call(conn, {:error, code}) when is_atom(code), do: Errors.send_error(conn, code)

  def call(conn, {:error, code, details}) when is_atom(code) and is_map(details),
    do: Errors.send_error(conn, code, details)

  def call(conn, nil), do: Errors.send_error(conn, :not_found)

  # As the router's plug for any path under /api that is not a route.
  def call(conn, :not_found), do: Errors.send_error(conn, :not_found)

  @doc "Any path under /api that is not one."
  def not_found(conn, _params), do: Errors.send_error(conn, :not_found)

  @doc "A changeset's errors, by field, worded as the web forms word them."
  @spec fields(Ecto.Changeset.t()) :: %{String.t() => [String.t()]}
  def fields(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&IdejoWeb.CoreComponents.translate_error/1)
    |> Map.new(fn {field, errors} -> {Atom.to_string(field), List.flatten(errors)} end)
  end
end

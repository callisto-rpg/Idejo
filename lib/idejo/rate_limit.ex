# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.RateLimit do
  @moduledoc """
  Rate limits (SP-05), counted in memory with Hammer (ETS, fixed windows; steward decision).

  `check/2` counts one more `action` for `id` (an IP address or a user id) and answers `:ok`
  or `{:error, :rate_limited}` past the limit. Limits per action:

    * per IP: `:request` (every request), `:sign_in`, `:sign_up`, `:reset_password`;
    * per user: `:commit` (every Enter), `:new_message`, `:new_topic`, `:report`, `:upload`.

  Off when `config :idejo, :rate_limits, enabled: false` (the test configuration; the rate
  limit tests turn it on).
  """
  use Hammer, backend: :ets

  @minute 60_000
  @hour 3_600_000

  @limits %{
    request: {300, @minute},
    sign_in: {10, @minute},
    sign_up: {5, @hour},
    reset_password: {5, @hour},
    commit: {240, @minute},
    new_message: {30, @minute},
    new_topic: {10, @hour},
    report: {20, @hour},
    upload: {30, @hour}
  }

  @type action ::
          :request
          | :sign_in
          | :sign_up
          | :reset_password
          | :commit
          | :new_message
          | :new_topic
          | :report
          | :upload

  @doc "The limit of an action: `{count, window in milliseconds}`."
  @spec limit(action()) :: {pos_integer(), pos_integer()}
  def limit(action), do: Map.fetch!(@limits, action)

  @doc """
  Counts one `action` by `id` and answers whether it is within the limit. `id` is anything
  that names who acts: an IP address tuple or a user id.
  """
  @spec check(action(), term()) :: :ok | {:error, :rate_limited}
  def check(action, id) do
    {count, window} = limit(action)

    cond do
      not enabled?() -> :ok
      match?({:allow, _}, hit({action, id}, window, count)) -> :ok
      true -> {:error, :rate_limited}
    end
  end

  defp enabled?, do: Application.get_env(:idejo, :rate_limits, []) |> Keyword.get(:enabled, true)
end

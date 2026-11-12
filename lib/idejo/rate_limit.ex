# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.RateLimit do
  @moduledoc """
  Rate limits (SP-05), counted in memory with Hammer (ETS, fixed windows; steward decision).

  `check/2` counts one more `action` for `id` (an IP address or a user id) and answers `:ok`
  or `{:error, :rate_limited}` past the limit. Limits per action:

    * per IP: `:request` (every request), `:sign_in`, `:sign_up`, `:reset_password`;
    * per device token of the official app (AP-18): `:api_token`, every request, 600 a
      minute (`config :idejo, :api_token_requests_per_minute`); per IP, `:api_oauth`;
    * per user: `:commit` (every Enter), `:new_message`, `:new_topic`, `:report`, `:upload`, `:react`, `:vote` (polls),
      `:push_subscribe` (PN-16), `:push_test` (PN-24).

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
    upload: {30, @hour},
    react: {120, @minute},
    vote: {120, @minute},
    # PN-16: every signed-in page load syncs the browser's subscription (PN-18).
    push_subscribe: {60, @minute},
    # PN-24: "Send test notification".
    push_test: {5, @minute},
    # AP-18: every request of one of the app's device tokens, overall (`config :idejo,
    # :api_token_requests_per_minute` changes it); each action keeps its own limit too.
    api_token: {600, @minute},
    # AP-08: the token endpoint, per IP address.
    api_oauth: {10, @minute}
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
          | :react
          | :vote
          | :push_subscribe
          | :push_test
          | :api_token
          | :api_oauth

  @doc "The limit of an action: `{count, window in milliseconds}`."
  @spec limit(action()) :: {pos_integer(), pos_integer()}
  def limit(:api_token),
    do: {Application.get_env(:idejo, :api_token_requests_per_minute, 600), @minute}

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

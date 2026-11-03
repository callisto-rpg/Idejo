# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.RateLimitWindow do
  @moduledoc """
  For tests that send an action up to its limit (SP-05): Hammer counts in fixed windows
  aligned to the clock (`div(now, window)`), so a burst that straddles a window's end starts
  counting again and the refusal comes late. `fresh/1` waits, when the current window has
  less than `room` left, until the next one starts, so the whole burst falls in one window.
  """

  # Far more than any burst takes; the wait happens in about one test in six.
  @room 10_000

  @doc "Waits until the window of `action` has at least `room` milliseconds left."
  @spec fresh(Idejo.RateLimit.action(), pos_integer()) :: :ok
  def fresh(action, room \\ @room) do
    {_limit, window} = Idejo.RateLimit.limit(action)
    left = window - rem(System.system_time(:millisecond), window)
    if left < room, do: Process.sleep(left + 50)
    :ok
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push do
  @moduledoc """
  Web push notifications (NO-05, PN-01 to PN-24; steward decision, 2026-10-24): standard Web
  Push (RFC 8030, 8291, 8292), with no vendor SDK or relay of our own.

  The server's VAPID keys are in `Idejo.Push.Vapid`. The "Push notifications" setting
  (PN-19, `push_enabled`, on by default) turns the whole feature off: no banner, no
  subscribing and no sending.
  """

  alias Idejo.Settings

  @doc "Whether push notifications are on for this server (PN-19)."
  @spec enabled?() :: boolean()
  def enabled?, do: Settings.get(:push_enabled) == "on"
end

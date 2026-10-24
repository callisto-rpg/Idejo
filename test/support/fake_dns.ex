# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.FakeDNS do
  @moduledoc """
  The push endpoint check's resolver in tests (`config :idejo, :push_resolver`): fixed
  answers, so tests need no network and can name hosts that resolve to private addresses
  (PN-16). Unknown names resolve to nothing.
  """

  @answers %{
    "fcm.googleapis.com" => [{142, 250, 74, 10}, {0x2A00, 0x1450, 0x4007, 0x80F, 0, 0, 0, 0x200A}],
    "updates.push.services.mozilla.com" => [{34, 117, 59, 81}],
    "web.push.apple.com" => [{17, 188, 182, 196}],
    "wns2-par02p.notify.windows.com" => [{52, 109, 8, 89}],
    # Not allowed by default: an administrator adds it (UnifiedPush).
    "ntfy.example.org" => [{93, 184, 215, 14}],
    # Allowed names that lead inside: one bad address among good ones is enough to refuse.
    "rebind.push.apple.com" => [{17, 188, 182, 197}, {10, 0, 0, 5}],
    "loopback.push.apple.com" => [{127, 0, 0, 1}],
    "ipv6-loopback.push.apple.com" => [{0, 0, 0, 0, 0, 0, 0, 1}],
    "metadata.push.apple.com" => [{169, 254, 169, 254}],
    "mapped.push.apple.com" => [{0, 0, 0, 0, 0, 0xFFFF, 0xC0A8, 0x0101}],
    "ula.push.apple.com" => [{0xFD12, 0x3456, 0, 0, 0, 0, 0, 1}]
  }

  @doc "The addresses of `host`, as `Idejo.Push.Endpoint.getaddrs/1` would give them."
  @spec getaddrs(charlist()) :: [:inet.ip_address()]
  def getaddrs(host), do: Map.get(@answers, to_string(host), [])
end

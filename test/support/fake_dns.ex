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
    "ula.push.apple.com" => [{0xFD12, 0x3456, 0, 0, 0, 0, 0, 1}],
    # Plugins' requests (Idejo.Plugins.Remote): a forums directory and forums, and one inside.
    "forums.idejo.test" => [{93, 184, 215, 20}],
    "garden.idejo.test" => [{93, 184, 215, 21}],
    "inside.idejo.test" => [{10, 0, 0, 9}],
    # The app's UnifiedPush distributors (AP-19): any host, public addresses only.
    "up.example.net" => [{93, 184, 215, 30}],
    "private.example.net" => [{192, 168, 1, 10}],
    "loopback.example.net" => [{127, 0, 0, 1}],
    "linklocal.example.net" => [{169, 254, 1, 1}],
    "cgnat.example.net" => [{100, 64, 0, 7}],
    "mapped.example.net" => [{0, 0, 0, 0, 0, 0xFFFF, 0x0A00, 0x0001}],
    "ula.example.net" => [{0xFD00, 0, 0, 0, 0, 0, 0, 1}],
    "multicast.example.net" => [{224, 0, 0, 1}],
    # Public until a test says otherwise (`answer/2`): DNS changing after registration.
    "changing.example.net" => [{93, 184, 215, 31}]
  }

  @doc "The addresses of `host`, as `Idejo.Push.Endpoint.getaddrs/1` would give them."
  @spec getaddrs(charlist()) :: [:inet.ip_address()]
  def getaddrs(host) do
    host = to_string(host)

    Map.get(Application.get_env(:idejo, :fake_dns_overrides, %{}), host) ||
      Map.get(@answers, host, [])
  end

  @doc "Makes `host` resolve to `addresses` from now on (tests that are not async)."
  @spec answer(String.t(), [:inet.ip_address()]) :: :ok
  def answer(host, addresses) do
    overrides = Application.get_env(:idejo, :fake_dns_overrides, %{})
    Application.put_env(:idejo, :fake_dns_overrides, Map.put(overrides, host, addresses))
  end

  @doc "Forgets every `answer/2`."
  @spec reset() :: :ok
  def reset, do: Application.delete_env(:idejo, :fake_dns_overrides)
end

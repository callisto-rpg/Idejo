# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.CryptoTest do
  use ExUnit.Case, async: true

  alias Idejo.Push.Crypto

  # RFC 8291, section 5: "Push Message Encryption Example".
  @plaintext "When I grow up, I want to be a watermelon"
  @auth "BTBZMqHH6r4Tts7J_aSIgg"
  @ua_private "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94"
  @ua_public "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
  @as_private "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw"
  @as_public "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8"
  @body "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml" <>
          "mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT" <>
          "pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"

  defp d(string), do: Base.url_decode64!(string, padding: false)

  @tag req: "PN-15"
  test "PN-15 encrypts exactly as RFC 8291's example" do
    body =
      Crypto.encrypt(@plaintext, d(@ua_public), d(@auth),
        sender: %{public: d(@as_public), private: d(@as_private)},
        salt: binary_part(d(@body), 0, 16)
      )

    assert body == d(@body)
    assert Crypto.decrypt(d(@body), d(@ua_private), d(@ua_public), d(@auth)) == {:ok, @plaintext}
  end

  @tag req: "PN-15"
  test "PN-15 each message has its own sender key and salt, readable only by its browser" do
    {ua_public, ua_private} = :crypto.generate_key(:ecdh, :prime256v1)
    auth = :crypto.strong_rand_bytes(16)
    message = ~s({"web_push":8030,"notification":{"title":"Ünïcode ✓"}})

    one = Crypto.encrypt(message, ua_public, auth)
    two = Crypto.encrypt(message, ua_public, auth)

    refute one == two
    assert Crypto.decrypt(one, ua_private, ua_public, auth) == {:ok, message}
    assert Crypto.decrypt(two, ua_private, ua_public, auth) == {:ok, message}

    {_other_public, other_private} = :crypto.generate_key(:ecdh, :prime256v1)
    assert Crypto.decrypt(one, other_private, ua_public, auth) == :error
    assert Crypto.decrypt(one, ua_private, ua_public, :crypto.strong_rand_bytes(16)) == :error

    # The body is the header (86 bytes), the message, its delimiter and the 16-byte tag.
    assert byte_size(one) == 86 + byte_size(message) + 1 + 16
  end

  @tag req: "PN-15"
  test "PN-15 signs a VAPID JWT for the push service's origin with ES256" do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)
    keys = %{public: public, private: private}

    header =
      Crypto.vapid_authorization(
        "https://updates.push.services.mozilla.com:443/wpush/v2/abc?x=1",
        keys,
        "mailto:owner@example.org",
        now: 1_800_000_000
      )

    assert "vapid t=" <> rest = header
    [jwt, "k=" <> k] = String.split(rest, ", ")
    assert d(k) == public

    [head, claims, signature] = String.split(jwt, ".")
    assert Jason.decode!(d(head)) == %{"typ" => "JWT", "alg" => "ES256"}

    assert Jason.decode!(d(claims)) == %{
             "aud" => "https://updates.push.services.mozilla.com",
             "exp" => 1_800_000_000 + 12 * 3600,
             "sub" => "mailto:owner@example.org"
           }

    <<r::unsigned-big-256, s::unsigned-big-256>> = d(signature)
    der = :public_key.der_encode(:"ECDSA-Sig-Value", {:"ECDSA-Sig-Value", r, s})
    assert :crypto.verify(:ecdsa, :sha256, head <> "." <> claims, der, [public, :prime256v1])
  end
end

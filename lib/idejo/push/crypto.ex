# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.Crypto do
  @moduledoc """
  The cryptography of web push (PN-15), on OTP's `:crypto` alone: no Hex library qualified
  (steward decision, 2026-10-24: the maintained one encrypts with the draft `aesgcm`, not
  RFC 8291's `aes128gcm`).

    * `encrypt/4`: a message for one browser subscription (RFC 8291, with the `aes128gcm`
      content coding of RFC 8188), as the body of a push request.
    * `vapid_authorization/3`: the request's `Authorization` header (RFC 8292), a JWT signed
      with the server's VAPID key (`Idejo.Push.Vapid`).

  `decrypt/4` does what a browser does, so tests can read what was sent.

  Changes to this module get an extra careful human review (DV-06).
  """

  # One record holds the whole message: payloads stay under 3 KB (PN-12).
  @record_size 4096
  @tag_size 16

  @doc """
  Encrypts `plaintext` for the subscription with public key `ua_public` (the 65-byte
  uncompressed point, `p256dh`) and authentication secret `auth` (16 bytes).

  A fresh sender key pair and salt are made for each message; `opts` may give them
  (`:sender` as `%{public: _, private: _}` and `:salt`) to reproduce RFC 8291's example.
  """
  @spec encrypt(binary(), binary(), binary(), keyword()) :: binary()
  def encrypt(plaintext, <<4, _::binary-size(64)>> = ua_public, auth, opts \\ [])
      when byte_size(auth) == 16 do
    %{public: as_public, private: as_private} = Keyword.get_lazy(opts, :sender, &generate/0)
    salt = Keyword.get_lazy(opts, :salt, fn -> :crypto.strong_rand_bytes(16) end)

    shared = :crypto.compute_key(:ecdh, ua_public, as_private, :prime256v1)
    {key, nonce} = content_keys(shared, auth, salt, ua_public, as_public)

    # The last (and only) record ends with the delimiter 0x02 (RFC 8188, section 2).
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_128_gcm, key, nonce, plaintext <> <<2>>, "", true)

    <<salt::binary-size(16), @record_size::32, byte_size(as_public)::8, as_public::binary,
      ciphertext::binary, tag::binary>>
  end

  @doc """
  Decrypts a body made by `encrypt/4`, as the browser holding `ua_private` does. Returns
  `{:ok, plaintext}` or `:error`.
  """
  @spec decrypt(binary(), binary(), binary(), binary()) :: {:ok, binary()} | :error
  def decrypt(body, ua_private, ua_public, auth) do
    with <<salt::binary-size(16), _rs::32, id_length::8, rest::binary>> <- body,
         <<as_public::binary-size(^id_length), sealed::binary>> <- rest,
         true <- byte_size(sealed) > @tag_size do
      shared = :crypto.compute_key(:ecdh, as_public, ua_private, :prime256v1)
      {key, nonce} = content_keys(shared, auth, salt, ua_public, as_public)
      ciphertext_size = byte_size(sealed) - @tag_size
      <<ciphertext::binary-size(^ciphertext_size), tag::binary>> = sealed

      case :crypto.crypto_one_time_aead(:aes_128_gcm, key, nonce, ciphertext, "", tag, false) do
        :error -> :error
        padded -> unpad(padded)
      end
    else
      _ -> :error
    end
  end

  # RFC 8291, section 3.4, then RFC 8188, section 2.2 and 2.3.
  defp content_keys(shared, auth, salt, ua_public, as_public) do
    ikm = hkdf(auth, shared, "WebPush: info" <> <<0>> <> ua_public <> as_public, 32)
    prk = :crypto.mac(:hmac, :sha256, salt, ikm)

    {expand(prk, "Content-Encoding: aes128gcm" <> <<0>>, 16),
     expand(prk, "Content-Encoding: nonce" <> <<0>>, 12)}
  end

  defp hkdf(salt, ikm, info, length),
    do: :crypto.mac(:hmac, :sha256, salt, ikm) |> expand(info, length)

  # One block of HKDF-Expand is enough: every length here is at most 32 bytes.
  defp expand(prk, info, length) when length <= 32,
    do: :crypto.mac(:hmac, :sha256, prk, info <> <<1>>) |> binary_part(0, length)

  # Padding is zeros after the delimiter; the last record's delimiter is 2.
  defp unpad(padded), do: unpad(padded, byte_size(padded))

  defp unpad(_padded, 0), do: :error

  defp unpad(padded, size) do
    case :binary.at(padded, size - 1) do
      0 -> unpad(padded, size - 1)
      2 -> {:ok, binary_part(padded, 0, size - 1)}
      _ -> :error
    end
  end

  @doc """
  The `Authorization` header of a push request to `endpoint` (RFC 8292): `vapid t=<JWT>,
  k=<public key>`. The JWT names the push service's origin (`aud`), the server's contact
  (`sub`, a `mailto:` or `https:` URL) and expires 12 hours from `now` (the RFC allows 24).
  """
  @spec vapid_authorization(
          String.t(),
          %{public: binary(), private: binary()},
          String.t(),
          keyword()
        ) ::
          String.t()
  def vapid_authorization(endpoint, %{public: public, private: private}, sub, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> System.system_time(:second) end)
    %URI{scheme: scheme, host: host, port: port} = URI.parse(endpoint)
    audience = URI.to_string(%URI{scheme: scheme, host: host, port: port})

    header = encode(Jason.encode!(%{typ: "JWT", alg: "ES256"}))
    claims = encode(Jason.encode!(%{aud: audience, exp: now + 12 * 3600, sub: sub}))
    signing_input = header <> "." <> claims

    {:"ECDSA-Sig-Value", r, s} =
      :public_key.der_decode(
        :"ECDSA-Sig-Value",
        :crypto.sign(:ecdsa, :sha256, signing_input, [private, :prime256v1])
      )

    # JWS takes the signature as r and s, 32 bytes each (RFC 7518, section 3.4), not DER.
    signature = <<r::unsigned-big-256, s::unsigned-big-256>>

    "vapid t=#{signing_input}.#{encode(signature)}, k=#{encode(public)}"
  end

  defp generate do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)
    %{public: public, private: private}
  end

  defp encode(binary), do: Base.url_encode64(binary, padding: false)
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.Vapid do
  @moduledoc """
  The server's VAPID key pair (PN-14, RFC 8292): a P-256 key that signs every push request,
  so push services know the pushes come from the server the browser subscribed to.

  Both halves are rows of the `settings` table, so backups carry them (AD-05), but they are
  not in `Idejo.Settings`'s definitions: no form can change them. The public key is stored as
  browsers take it (`applicationServerKey`: the uncompressed point, URL-safe Base64); the
  private key is encrypted like other secrets (`Idejo.Settings.Secret`), so a database dump
  alone cannot sign pushes. A migration makes the pair on every install (before the setup
  wizard, so new installs have one too); `bin/idejo-admin rotate-push-keys` replaces it.

  Changes to this module get an extra careful human review (DV-06).
  """

  alias Idejo.Repo
  alias Idejo.Settings.{Secret, Setting}

  @public "vapid_public_key"
  @private "vapid_private_key"

  @type keys :: %{public: binary(), private: binary()}

  @doc "Makes a new P-256 key pair: the 65-byte uncompressed public point and 32-byte private key."
  @spec generate() :: keys()
  def generate do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)
    %{public: public, private: private}
  end

  @doc """
  The stored key pair, or `{:error, :missing}` when there is none, or `{:error, :unreadable}`
  when the private key can no longer be decrypted (`SECRET_KEY_BASE` changed).
  """
  @spec keys() :: {:ok, keys()} | {:error, :missing | :unreadable}
  def keys do
    stored = Map.new(Repo.all(rows()), &{&1.key, &1.value})

    with {:ok, public} <- fetch(stored, @public),
         {:ok, sealed} <- fetch(stored, @private) do
      case Secret.decrypt(sealed) do
        nil -> {:error, :unreadable}
        private -> {:ok, %{public: decode!(public), private: decode!(private)}}
      end
    end
  end

  @doc "The public key as browsers take it (`applicationServerKey`), or nil when there is none."
  @spec public_key() :: String.t() | nil
  def public_key do
    case Repo.get(Setting, @public) do
      %Setting{value: value} -> value
      nil -> nil
    end
  end

  @doc """
  Replaces the key pair with a new one. Every browser subscription was made with the old
  public key, so none of them will take pushes signed with the new one.
  """
  @spec rotate() :: {:ok, String.t()}
  def rotate do
    keys = generate()
    now = DateTime.utc_now(:second)

    Repo.insert_all(Setting, rows(keys, now),
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )

    {:ok, encode(keys.public)}
  end

  @doc """
  The two `settings` rows for `keys`, as `Repo.insert_all/3` takes them (the migration that
  makes the first pair uses it too).
  """
  @spec rows(keys(), DateTime.t()) :: [map()]
  def rows(%{public: public, private: private}, now) do
    [
      %{key: @public, value: encode(public), inserted_at: now, updated_at: now},
      %{key: @private, value: Secret.encrypt(encode(private)), inserted_at: now, updated_at: now}
    ]
  end

  defp rows do
    import Ecto.Query
    from s in Setting, where: s.key in [@public, @private]
  end

  defp fetch(stored, key) do
    case stored do
      %{^key => value} -> {:ok, value}
      _ -> {:error, :missing}
    end
  end

  defp encode(binary), do: Base.url_encode64(binary, padding: false)
  defp decode!(string), do: Base.url_decode64!(string, padding: false)
end

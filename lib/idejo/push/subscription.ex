# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Push.Subscription do
  @moduledoc """
  A browser that takes web push for a user (PN-13): its push service `endpoint` and the keys
  messages are encrypted with (`p256dh`, the browser's P-256 public key, and `auth`, its
  16-byte secret, both URL-safe Base64 as `PushSubscription.toJSON()` gives them, stored
  without padding).

  Changes to this module get an extra careful human review (DV-06).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "push_subscriptions" do
    belongs_to :user, Idejo.Accounts.User
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    field :user_agent, :string
    field :session_id, :string
    field :last_success_at, :utc_datetime_usec
    field :failure_count, :integer, default: 0

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end

  @doc """
  Checks what a browser sent: an endpoint of reasonable length and keys that decode to a
  point on P-256 and a 16-byte secret. Whether the endpoint may be reached is
  `Idejo.Push.Endpoint`'s question.
  """
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:endpoint, :p256dh, :auth])
    |> validate_required([:endpoint, :p256dh, :auth])
    |> validate_length(:endpoint, max: 2048)
    |> update_change(:p256dh, &String.trim_trailing(&1, "="))
    |> update_change(:auth, &String.trim_trailing(&1, "="))
    |> validate_change(:p256dh, fn :p256dh, key ->
      if public_key?(key), do: [], else: [p256dh: "is not a P-256 public key"]
    end)
    |> validate_change(:auth, fn :auth, secret ->
      case decode(secret) do
        {:ok, <<_::binary-size(16)>>} -> []
        _ -> [auth: "is not a 16-byte secret"]
      end
    end)
  end

  @doc "The browser's public key and secret as binaries, for `Idejo.Push.Crypto.encrypt/4`."
  @spec keys(t()) :: {binary(), binary()}
  def keys(%__MODULE__{p256dh: p256dh, auth: auth}),
    do: {Base.url_decode64!(p256dh, padding: false), Base.url_decode64!(auth, padding: false)}

  defp public_key?(key) do
    case decode(key) do
      {:ok, <<4, _::binary-size(64)>> = point} ->
        # Only a point on the curve gives a shared secret; anything else raises.
        {_public, private} = :crypto.generate_key(:ecdh, :prime256v1)
        _ = :crypto.compute_key(:ecdh, point, private, :prime256v1)
        true

      _ ->
        false
    end
  rescue
    ErlangError -> false
  end

  defp decode(string), do: Base.url_decode64(string, padding: false)
end

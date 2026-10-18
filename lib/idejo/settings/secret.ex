# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Settings.Secret do
  @moduledoc """
  Encrypts secret settings, such as the SMTP password (AD-08), before they are stored.

  The key is derived from `SECRET_KEY_BASE`, so a database dump alone does not reveal the
  secret. If `SECRET_KEY_BASE` changes, saved secrets can no longer be read and must be
  entered again.
  """

  alias Plug.Crypto.{KeyGenerator, MessageEncryptor}

  @salt "idejo settings secret"
  @sign_salt "idejo settings secret signature"

  @doc """
  Encrypts a value for storage.
  """
  @spec encrypt(String.t()) :: String.t()
  def encrypt(value) when is_binary(value) do
    MessageEncryptor.encrypt(value, key(@salt), key(@sign_salt))
  end

  @doc """
  Decrypts a stored value, or returns `nil` when it cannot be read.
  """
  @spec decrypt(String.t()) :: String.t() | nil
  def decrypt(stored) when is_binary(stored) do
    case MessageEncryptor.decrypt(stored, key(@salt), key(@sign_salt)) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  # The endpoint's secret_key_base is the one secret every install already has.
  defp key(salt) do
    :idejo
    |> Application.fetch_env!(IdejoWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
    |> KeyGenerator.generate(salt, length: 32)
  end
end

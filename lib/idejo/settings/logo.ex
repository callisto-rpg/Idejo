# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Settings.Logo do
  @moduledoc """
  The forum's own logo (AD-11), shown in the header before the server's name in place of
  Idejo's small logo. Administrators upload it in Admin → Settings: `set/2` stores the image
  (`Idejo.Uploads.store_logo/2`) and saves its address in the `brand_logo` setting, audited as
  any `settings.update`; `remove/1` goes back to Idejo's logo. A replaced logo's file and row
  are deleted. While the setting names it, `Uploads.delete_unused/1` keeps the upload.
  """

  alias Idejo.Accounts.User
  alias Idejo.Settings
  alias Idejo.Uploads

  @default "/images/logo-small.svg"

  @doc """
  The address of the header's logo: the forum's own, or Idejo's small logo. Takes the
  `brand_logo` setting when the caller has read it already.
  """
  @spec url(String.t()) :: String.t()
  def url(setting \\ Settings.get(:brand_logo))
  def url(""), do: @default
  def url(url), do: url

  @doc "Makes the image at `path` the forum's logo, as `admin`."
  @spec set(User.t(), Path.t()) :: {:ok, String.t()} | {:error, atom() | Ecto.Changeset.t()}
  def set(%User{} = admin, path) do
    with {:ok, upload} <- Uploads.store_logo(admin, path) do
      replace(admin, Uploads.url(upload))
    end
  end

  @doc "Goes back to Idejo's small logo, as `admin`."
  @spec remove(User.t()) :: {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def remove(%User{} = admin), do: replace(admin, "")

  defp replace(admin, new) do
    old = Settings.get(:brand_logo)

    with {:ok, _settings} <- Settings.update_settings(admin, %{brand_logo: new}) do
      if old != new, do: Uploads.delete(upload_id(old))
      {:ok, url()}
    end
  end

  defp upload_id("/uploads/" <> name), do: Path.rootname(name)
  defp upload_id(_none), do: nil
end

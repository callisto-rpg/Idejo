# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Source do
  @moduledoc """
  Where users get the source code this server runs (LI-03, AGPL section 13).

  By default the link points at the upstream repository at the exact commit the release
  was built from, read from `.git` at compile time. A server running modified code must set
  `IDEJO_SOURCE_URL` to where its own source is published; that URL is then used as is.
  """

  alias Idejo.Source.Git

  @git_dir Path.expand("../../.git", __DIR__)
  for file <- Git.revision_files(@git_dir), do: @external_resource(file)

  @revision Git.read_revision(@git_dir)

  @doc """
  The commit this release was built from, or `nil` when it was built without `.git`.
  """
  @spec revision() :: String.t() | nil
  def revision, do: @revision

  @doc """
  The "Source code" link shown in the footer.
  """
  @spec url() :: String.t()
  def url do
    case Application.get_env(:idejo, :source_url) do
      url when is_binary(url) and url != "" -> url
      _ -> upstream_url(revision())
    end
  end

  @doc false
  def upstream_url(nil), do: Application.fetch_env!(:idejo, :upstream_source_url)
  def upstream_url(revision), do: upstream_url(nil) <> "/tree/" <> revision
end

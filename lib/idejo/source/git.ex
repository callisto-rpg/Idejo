# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Source.Git do
  @moduledoc """
  Reads the checked-out commit from a `.git` directory without the git program, for
  `Idejo.Source` (LI-03).
  """

  @doc """
  The files that hold the checked-out commit, so a module reading it at compile time can
  declare them as external resources.
  """
  @spec revision_files(Path.t()) :: [Path.t()]
  # Paths come from the build's own .git at compile time, never from a request.
  # sobelow_skip ["Traversal.FileModule"]
  def revision_files(git_dir) do
    head = Path.join(git_dir, "HEAD")

    case File.read(head) do
      {:ok, "ref: " <> ref} ->
        [head, Path.join(git_dir, String.trim(ref)), Path.join(git_dir, "packed-refs")]

      _ ->
        [head]
    end
  end

  @doc """
  Reads the commit checked out in a `.git` directory, or `nil` when it cannot be found.

  Only `HEAD`, loose refs and `packed-refs` are read; the release image contains no other
  part of `.git`.
  """
  @spec read_revision(Path.t()) :: String.t() | nil
  # Paths come from the build's own .git at compile time, never from a request.
  # sobelow_skip ["Traversal.FileModule"]
  def read_revision(git_dir) do
    case File.read(Path.join(git_dir, "HEAD")) do
      {:ok, head} -> head |> String.trim() |> resolve_head(git_dir)
      {:error, _} -> nil
    end
  end

  defp resolve_head("ref: " <> ref, git_dir), do: resolve_ref(git_dir, ref)
  defp resolve_head(sha, _git_dir), do: if(sha?(sha), do: sha)

  # Paths come from the build's own .git at compile time, never from a request.
  # sobelow_skip ["Traversal.FileModule"]
  defp resolve_ref(git_dir, ref) do
    case File.read(Path.join(git_dir, ref)) do
      {:ok, sha} -> resolve_head(String.trim(sha), git_dir)
      {:error, _} -> packed_ref(git_dir, ref)
    end
  end

  # Paths come from the build's own .git at compile time, never from a request.
  # sobelow_skip ["Traversal.FileModule"]
  defp packed_ref(git_dir, ref) do
    with {:ok, packed} <- File.read(Path.join(git_dir, "packed-refs")),
         [sha] <-
           for(line <- String.split(packed, "\n"), [sha, ^ref] <- [String.split(line)], do: sha),
         true <- sha?(sha) do
      sha
    else
      _ -> nil
    end
  end

  defp sha?(value), do: value =~ ~r/\A[0-9a-f]{40}([0-9a-f]{24})?\z/
end

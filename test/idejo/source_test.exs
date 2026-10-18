# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.SourceTest do
  # Changes application env, so not async.
  use ExUnit.Case, async: false

  alias Idejo.Source
  alias Idejo.Source.Git

  @sha "4301e85575f392ef93856450d4902e91daf0417b"

  @moduletag :tmp_dir

  defp write!(dir, path, content) do
    path = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  setup do
    on_exit(fn -> Application.delete_env(:idejo, :source_url) end)
  end

  describe "reading the built commit" do
    @tag req: "LI-03"
    test "LI-03 reads a branch's commit from a loose ref", %{tmp_dir: dir} do
      write!(dir, "HEAD", "ref: refs/heads/main\n")
      write!(dir, "refs/heads/main", @sha <> "\n")
      assert Git.read_revision(dir) == @sha
    end

    @tag req: "LI-03"
    test "LI-03 reads a branch's commit from packed refs", %{tmp_dir: dir} do
      write!(dir, "HEAD", "ref: refs/heads/main\n")
      write!(dir, "packed-refs", "# pack-refs with: peeled\n#{@sha} refs/heads/main\n")
      assert Git.read_revision(dir) == @sha
    end

    @tag req: "LI-03"
    test "LI-03 reads a detached commit", %{tmp_dir: dir} do
      write!(dir, "HEAD", @sha <> "\n")
      assert Git.read_revision(dir) == @sha
    end

    @tag req: "LI-03"
    test "LI-03 gives nil without a usable .git", %{tmp_dir: dir} do
      assert Git.read_revision(Path.join(dir, "missing")) == nil

      write!(dir, "HEAD", "ref: refs/heads/gone\n")
      assert Git.read_revision(dir) == nil

      write!(dir, "HEAD", "not a commit\n")
      assert Git.read_revision(dir) == nil
    end
  end

  describe "url/0" do
    @tag req: "LI-03"
    test "LI-03 links the upstream repository at the commit the release was built from" do
      upstream = Application.fetch_env!(:idejo, :upstream_source_url)

      assert Source.url() ==
               if(Source.revision(),
                 do: upstream <> "/tree/" <> Source.revision(),
                 else: upstream
               )

      assert Source.upstream_url(@sha) == upstream <> "/tree/" <> @sha
      assert Source.upstream_url(nil) == upstream
    end

    @tag req: "LI-03"
    test "LI-03 a modified server links its own source" do
      Application.put_env(:idejo, :source_url, "https://git.example.org/our-idejo")
      assert Source.url() == "https://git.example.org/our-idejo"
    end

    @tag req: "LI-03"
    test "LI-03 an empty IDEJO_SOURCE_URL falls back to upstream" do
      Application.put_env(:idejo, :source_url, "")
      assert Source.url() =~ Application.fetch_env!(:idejo, :upstream_source_url)
    end
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Rules live in contexts (AP-01 preparation; CLAUDE.md → Conventions): the web layer never
# reaches the database, and the contexts never depend on the web layer, but for the few
# references listed here with their reason. A new exception is a steward decision.
defmodule Idejo.LayeringTest do
  use ExUnit.Case, async: true

  # Every context may use these: the event bus and a cryptography library, not the web.
  @everywhere ~w(Phoenix.PubSub Plug.Crypto)

  # File => what it may reference, and why.
  @allowed %{
    # Emails, push payloads and digests are written in the context that sends them, in the
    # one Gettext backend (CLAUDE.md: the only web module a context may reference).
    "lib/idejo/accounts/user_notifier.ex" => ~w(IdejoWeb.Gettext gettext),
    "lib/idejo/notifications/digest.ex" => ~w(IdejoWeb.Gettext gettext),
    "lib/idejo/push/payload.ex" => ~w(IdejoWeb.Gettext gettext),
    # The warning's push notification (MO-02).
    "lib/idejo/moderation/warnings.ex" => ~w(IdejoWeb.Gettext gettext),
    # Stored text that excerpts, emails and pushes all show: "(spoiler)" and "the topic".
    "lib/idejo/forum.ex" => ~w(IdejoWeb.Gettext gettext),
    "lib/idejo/messages.ex" => ~w(IdejoWeb.Gettext gettext),
    # The application starts the endpoint and its telemetry.
    "lib/idejo/application.ex" => ~w(IdejoWeb.Endpoint IdejoWeb.Telemetry),
    # The command line disconnects sessions when the endpoint runs (AD-09).
    "lib/idejo/release.ex" => ~w(IdejoWeb.Endpoint IdejoWeb.UserAuth),
    # Secrets are derived from the endpoint's secret_key_base.
    "lib/idejo/settings/secret.ex" => ~w(IdejoWeb.Endpoint)
  }

  test "the web layer never calls Repo or builds an Ecto query" do
    offenders =
      for path <- Path.wildcard("lib/idejo_web/**/*.{ex,heex}"),
          {line, n} <- code_lines(path),
          Regex.match?(~r/\bRepo\.|Ecto\.Query|import Ecto\b|\bfrom\(/, line),
          do: "#{path}:#{n}: #{String.trim(line)}"

    assert offenders == [], """
    The web layer must go through a context (CLAUDE.md, "Rules live in contexts"):

    #{Enum.join(offenders, "\n")}
    """
  end

  test "contexts never depend on the web layer, but for the listed exceptions" do
    offenders =
      for path <- Path.wildcard("lib/idejo/**/*.ex"),
          {line, n} <- code_lines(path),
          ref <- Regex.scan(~r/\b(?:Phoenix\.\w+|IdejoWeb\.\w+|Plug\.\w+|gettext)\b/, line),
          ref = hd(ref),
          ref not in @everywhere,
          ref not in Map.get(@allowed, path, []),
          do: "#{path}:#{n}: #{ref}"

    assert offenders == [], """
    A context must not reference the web layer (Phoenix, Plug, IdejoWeb, gettext). Return
    data and error atoms; the web layer words them:

    #{Enum.join(offenders, "\n")}
    """
  end

  test "every listed exception is still needed" do
    for {path, refs} <- @allowed, ref <- refs do
      used? =
        Enum.any?(code_lines(path), fn {line, _n} ->
          Regex.match?(~r/\b#{Regex.escape(ref)}\b/, line)
        end)

      assert used?, "#{path} no longer uses #{ref}: take it off the list"
    end
  end

  # The file's lines of code: comments, docs and other heredocs left out.
  defp code_lines(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, fn {line, n}, {acc, heredoc?} ->
      trimmed = String.trim(line)
      toggles? = rem(length(String.split(line, ~s("""))) - 1, 2) == 1

      cond do
        toggles? -> {acc, not heredoc?}
        heredoc? -> {acc, true}
        String.starts_with?(trimmed, "#") -> {acc, false}
        Regex.match?(~r/^@(moduledoc|doc|typedoc)\s/, trimmed) -> {acc, false}
        true -> {[{line, n} | acc], false}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end

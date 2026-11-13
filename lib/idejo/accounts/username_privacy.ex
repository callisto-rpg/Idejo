# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.UsernamePrivacy do
  @moduledoc """
  AC-09 (steward decision, 2026-11-06): accounts made by a sign-in with a provider that gave
  the email as `preferred_username` were named after the email (`jane.doe@example.org` →
  `@jane_doe_example_org`), which showed the address to everyone. `rename_all/0`, run once by
  a migration, renames each such account (linked to a provider, its username the email as
  `Accounts.free_username/2` made it, with or without its `_N` suffix) after its display
  name, or `member`, and a display name that is the email becomes the new username. Audited
  `user.rename` (no admin). Text that @mentioned the old name (messages and their earlier
  versions, bios, scheduled messages, automessages, info boxes) is rewritten to the new
  one, in the Markdown and in the stored links' text, so the email shows nowhere.
  """
  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.{User, UserIdentity, Usernames}
  alias Idejo.Audit.Entry
  alias Idejo.Repo

  @doc "Renames every account named after its email; returns how many."
  @spec rename_all() :: non_neg_integer()
  def rename_all do
    linked = from i in UserIdentity, select: i.user_id

    from(u in User,
      where: u.id in subquery(linked),
      select: [:id, :email, :username, :display_name]
    )
    |> Repo.all()
    |> Enum.filter(&from_email?(&1.username, &1.email))
    |> Enum.map(&rename/1)
    |> length()
  end

  @doc "Whether `username` was made from `email` by `Accounts.free_username/2`."
  @spec from_email?(String.t(), String.t()) :: boolean()
  def from_email?(username, email) when is_binary(username) and is_binary(email) do
    base =
      email |> String.replace(~r/[^A-Za-z0-9_]/, "_") |> String.slice(0, 30) |> String.downcase()

    short = String.slice(base, 0, 25) <> "_"
    name = String.downcase(username)

    String.contains?(email, "@") and
      (name == base or
         (String.starts_with?(name, short) and
            String.slice(name, String.length(short)..-1//1) =~ ~r/\A[0-9]+\z/))
  end

  def from_email?(_username, _email), do: false

  defp rename(%User{} = user) do
    shown? = String.contains?(user.display_name || "", "@")
    username = Accounts.free_username(if(shown?, do: nil, else: user.display_name))
    changes = [username: username] ++ if(shown?, do: [display_name: username], else: [])

    Repo.transact(fn ->
      {1, _} = Repo.update_all(from(u in User, where: u.id == ^user.id), set: changes)
      Usernames.rewrite_mentions(user.username, username)

      Repo.insert(%Entry{
        change: "user.rename",
        before: %{"username" => user.username, "reason" => "named after the email"},
        after: %{"username" => username}
      })
    end)
  end
end

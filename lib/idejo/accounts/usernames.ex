# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Accounts.Usernames do
  @moduledoc """
  AC-04, changing one's username (steward request, 2026-11-13, replacing "the username never
  changes"). From Profile and account, with the current password or a fresh sign-in through
  the provider (`{:oidc, at}`, as deleting an account), at most once every 30 days
  (`users.username_changed_at`). The name given up stays reserved 30 days for whoever gave it
  up (`released_usernames`: sign-up, `Accounts.free_username/2` and other members' changes
  refuse it), so mentions written meanwhile never reach a stranger. Every stored @mention of
  the old name (messages and their earlier versions, bios, scheduled messages, automessages,
  info boxes; Markdown and the links' text) becomes the new one in the same transaction, with
  an `update` activity (FD-02) and the audit entry `user.rename` (no admin; the account's
  `uri`, the old and new names).

  The group's inbox may send the change to every forum (`Idejo.Community.SharedSettings`,
  section `username`): there it was confirmed on the inbox, so `change_vouched/2` asks for no
  password; the 30 days and the reservations hold on each forum.
  """
  import Ecto.Query

  alias Idejo.Accounts
  alias Idejo.Accounts.{OIDC, User}
  alias Idejo.{Audit, Federation, Repo}

  @days 30

  @doc "How many days between two changes, and how long a name given up stays reserved."
  @spec days() :: pos_integer()
  def days, do: @days

  @doc """
  Changes `user`'s username to `username`, confirmed by their current password or
  `{:oidc, at}`. The same name gives `{:ok, user}` and changes nothing.
  """
  @spec change(User.t(), String.t() | nil, String.t() | {:oidc, integer() | nil} | nil) ::
          {:ok, User.t()}
          | {:error,
             :invalid_password
             | :reauthentication
             | {:too_soon, DateTime.t()}
             | Ecto.Changeset.t()}
  def change(%User{} = user, username, confirmation) do
    with :ok <- confirmed(user, confirmation), do: change_vouched(user, username)
  end

  @doc """
  Changes the username without asking for a password: only for a change the member already
  confirmed elsewhere (the group's inbox, through a `settings` ticket).
  """
  @spec change_vouched(User.t(), String.t() | nil) ::
          {:ok, User.t()} | {:error, {:too_soon, DateTime.t()} | Ecto.Changeset.t()}
  def change_vouched(%User{} = user, username) do
    case User.username_changeset(user, %{username: username}) do
      %Ecto.Changeset{valid?: true, changes: changes} when not is_map_key(changes, :username) ->
        {:ok, user}

      %Ecto.Changeset{valid?: true} = changeset ->
        case next_change_at(user) do
          nil -> Repo.transact(fn -> rename(user, changeset) end)
          at -> {:error, {:too_soon, at}}
        end

      changeset ->
        {:error, changeset}
    end
  end

  @doc "When `user` may change their username again, or nil when they may now."
  @spec next_change_at(User.t()) :: DateTime.t() | nil
  def next_change_at(%User{username_changed_at: nil}), do: nil

  def next_change_at(%User{username_changed_at: at}) do
    next = DateTime.add(at, @days, :day)
    if DateTime.compare(next, DateTime.utc_now()) == :gt, do: next
  end

  @doc """
  Whether `username` was given up in the last 30 days by someone other than `user_id` (nil:
  anyone).
  """
  @spec reserved?(String.t(), Ecto.UUID.t() | nil) :: boolean()
  def reserved?(username, user_id) when is_binary(username) do
    since = DateTime.add(DateTime.utc_now(:second), -@days, :day)

    query =
      from r in "released_usernames",
        where:
          fragment("lower(?)", r.username) == ^String.downcase(username) and
            r.released_at > type(^since, :utc_datetime)

    query =
      if user_id,
        do: where(query, [r], r.user_id != type(^user_id, Ecto.UUID)),
        else: query

    Repo.exists?(query)
  end

  def reserved?(_username, _user_id), do: false

  defp confirmed(user, {:oidc, at}) do
    if OIDC.fresh_reauth?(at) and OIDC.identity(user), do: :ok, else: {:error, :reauthentication}
  end

  defp confirmed(user, password) do
    if Accounts.password_allowed?(user) and User.valid_password?(user, password || ""),
      do: :ok,
      else: {:error, :invalid_password}
  end

  defp rename(user, changeset) do
    now = DateTime.utc_now(:second)
    old = user.username

    with {:ok, renamed} <-
           changeset |> Ecto.Changeset.put_change(:username_changed_at, now) |> Repo.update(),
         :ok <- release(user, renamed.username, now),
         :ok <- rewrite_mentions(old, renamed.username),
         {:ok, _} <- Repo.insert(activity(renamed)),
         {:ok, _} <-
           Audit.record(nil, "user.rename", %{"uri" => user.uri, "username" => old}, %{
             "username" => renamed.username
           }) do
      {:ok, renamed}
    end
  end

  # The old name, unless only its case changed.
  defp release(user, new, now) do
    if String.downcase(user.username) != String.downcase(new) do
      Repo.insert_all(
        "released_usernames",
        [
          %{
            username: user.username,
            user_id: Ecto.UUID.dump!(user.id),
            released_at: DateTime.to_naive(now)
          }
        ],
        on_conflict: {:replace, [:user_id, :released_at]},
        conflict_target: :username
      )
    end

    :ok
  end

  defp activity(user) do
    Federation.activity_changeset(%{
      actor_uri: user.uri,
      verb: "update",
      object_uri: user.uri,
      payload: %{"type" => "Person", "username" => user.username, "name" => user.display_name}
    })
  end

  # Where text can @mention someone: {table, Markdown column, its stored HTML column or nil}.
  @texts [
    {"messages", :body_md, :body_html},
    {"message_versions", :body_md, nil},
    {"users", :bio_md, :bio_html},
    {"scheduled_messages", :body_md, nil},
    {"automessages", :body_md, nil},
    {"info_boxes", :body_md, :body_html}
  ]

  @doc """
  Rewrites every stored @mention of `old` to `new`: in the Markdown, `@old` not inside a
  longer name or an address; in the stored HTML, a mention link's text. Usernames hold only
  letters, digits and underscores: nothing to escape.
  """
  @spec rewrite_mentions(String.t(), String.t()) :: :ok
  def rewrite_mentions(old, new) do
    pattern = "(?<![A-Za-z0-9_@.])@" <> old <> "(?![A-Za-z0-9_])"
    mention = "@" <> new
    {link, new_link} = {">@" <> old <> "<", ">@" <> new <> "<"}

    for {table, md, html} <- @texts do
      query = from t in table, where: fragment("? ~* ?", field(t, ^md), ^pattern)

      sets =
        [{md, replaced(md, pattern, mention)}] ++
          if(html, do: [{html, replaced(html, link, new_link)}], else: [])

      Repo.update_all(update(query, set: ^sets), [])
    end

    :ok
  end

  defp replaced(column, pattern, replacement),
    do:
      dynamic(
        [t],
        fragment("regexp_replace(?, ?, ?, 'gi')", field(t, ^column), ^pattern, ^replacement)
      )
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AC04UsernameChangeTest do
  @moduledoc """
  AC-04, changing one's username (steward request, 2026-11-13; `Idejo.Accounts.Usernames`):
  confirmed by the password, once every 30 days, the old name reserved 30 days for whoever
  gave it up, every @mention of it following, audited. Not async: the rewrite of mentions
  runs over every message.
  """
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query
  import Idejo.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Idejo.Accounts
  alias Idejo.Accounts.User
  alias Idejo.Audit.Entry
  alias Idejo.Messages.Message
  alias Idejo.Repo

  defp named(base), do: user_fixture(%{username: unique_username(base)})

  # Moves a time back, as if `days` had passed.
  defp days_ago(days), do: DateTime.add(DateTime.utc_now(:second), -days, :day)

  @tag req: "AC-04"
  test "AC-04 a member changes their username with their password; mentions follow, audited" do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Idejo.Forum.create_category(admin, %{"name" => "General"})
    ada = named("ada")
    old = ada.username
    new = old <> "_k"

    {:ok, topic} =
      Idejo.Forum.create_topic(admin, general, %{
        "title" => "Hello",
        "body" => "Welcome @#{old}! Not @#{old}_2 nor x@#{old}.org."
      })

    [message] = Idejo.Forum.list_messages(topic)
    assert message.body_html =~ ">@#{old}</a>"

    assert Accounts.change_username(ada, new, "wrong password") == {:error, :invalid_password}
    assert Repo.get!(User, ada.id).username == old

    assert {:ok, %User{username: ^new} = renamed} =
             Accounts.change_username(ada, new, valid_user_password())

    assert renamed.username_changed_at

    message = Repo.get!(Message, message.id)
    assert message.body_md == "Welcome @#{new}! Not @#{old}_2 nor x@#{old}.org."
    assert message.body_html =~ ~s(href="/u/#{ada.id}" rel="noopener noreferrer">@#{new}</a>)
    refute message.body_html =~ ">@#{old}<"

    entry = Repo.one!(from e in Entry, where: e.change == "user.rename" and is_nil(e.admin_id))
    assert entry.before == %{"uri" => ada.uri, "username" => old}
    assert entry.after == %{"username" => new}

    # The same name changes nothing; an invalid one is refused with the form's errors.
    assert {:ok, ^renamed} = Accounts.change_username(renamed, new, valid_user_password())

    assert {:error, %Ecto.Changeset{} = changeset} =
             Accounts.change_username(renamed, "no spaces", valid_user_password())

    assert changeset.errors[:username]
  end

  @tag req: "AC-04"
  test "AC-04 once every 30 days, the old name reserved 30 days for whoever gave it up" do
    ada = named("ada")
    bob = named("bob")
    old = ada.username

    {:ok, ada} = Accounts.change_username(ada, old <> "_k", valid_user_password())

    assert {:error, {:too_soon, at}} =
             Accounts.change_username(ada, old <> "_j", valid_user_password())

    assert DateTime.diff(at, DateTime.utc_now(), :day) in 29..30

    # Nobody else takes the old name, not by changing theirs nor by signing up.
    assert {:error, changeset} = Accounts.change_username(bob, old, valid_user_password())
    assert {"was given up recently and is reserved for now", _} = changeset.errors[:username]
    refute Accounts.free_username(old) == old

    # Its owner takes it back once their 30 days have passed.
    Repo.update_all(from(u in User, where: u.id == ^ada.id),
      set: [username_changed_at: days_ago(31)]
    )

    ada = Repo.get!(User, ada.id)
    assert Accounts.username_next_change_at(ada) == nil

    assert {:ok, %User{username: ^old}} =
             Accounts.change_username(ada, old, valid_user_password())

    # A name given up more than 30 days ago is free again.
    carl = named("carl")
    given_up = carl.username
    {:ok, _} = Accounts.change_username(carl, given_up <> "_x", valid_user_password())

    Repo.update_all(from(r in "released_usernames"),
      set: [released_at: DateTime.to_naive(days_ago(31))]
    )

    assert {:ok, _} = Accounts.change_username(bob, given_up, valid_user_password())
  end

  @tag req: "AC-04"
  test "AC-04 Profile and account changes the username", %{conn: conn} do
    ada = named("ada")
    new = ada.username <> "_k"
    conn = log_in_user(conn, ada)

    {:ok, view, _html} = live(conn, ~p"/users/settings")
    assert has_element?(view, "#username-help", "@" <> ada.username)

    html =
      view
      |> form("#username-form", username: %{username: "a b"})
      |> render_change()

    assert html =~ "may only contain letters, digits and underscores"

    view
    |> form("#username-form", username: %{username: new, password: "wrong password"})
    |> render_submit()

    assert render(view) =~ "That is not your current password."
    assert Repo.get!(User, ada.id).username == ada.username

    fields = %{username: new, password: valid_user_password()}

    assert {:error, {:redirect, %{to: to}}} =
             view |> form("#username-form", username: fields) |> render_submit()

    assert to == "/users/settings?tab=profile#username-heading"
    assert Repo.get!(User, ada.id).username == new

    {:ok, view, _html} = live(conn, ~p"/users/settings")
    refute has_element?(view, "#username-form")
    assert has_element?(view, "#username-wait")
  end
end

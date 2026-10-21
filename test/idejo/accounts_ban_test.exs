# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccountsBanTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Accounts
  alias Idejo.Forum
  alias Idejo.Moderation.Action

  setup do
    %{moderator: user_with_role_fixture(:moderator), user: user_fixture()}
  end

  defp in_days(n), do: DateTime.add(DateTime.utc_now(), n * 86_400, :second)

  @tag req: "MO-02"
  test "MO-02 a ban stops sign-in and ends every session at once, logged", %{
    moderator: moderator,
    user: user
  } do
    token = Accounts.generate_user_session_token(user)
    assert Accounts.get_user_by_session_token(token)
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, topic} = Forum.create_topic(user, general, %{"title" => "Mine", "body" => "Stays"})

    {:ok, {banned, _socket_ids}} = Accounts.ban_user(moderator, user, in_days(7), "Spam")
    assert Accounts.banned?(banned)
    assert Accounts.get_user_by_session_token(token) == nil
    # Its messages stay.
    assert [%{body_md: "Stays"}] = Forum.list_messages(topic)

    entry = Repo.one!(from a in Action, where: a.action == "user.ban")
    assert {entry.target_type, entry.target_id, entry.reason} == {"user", user.id, "Spam"}
    assert entry.details["until"] == DateTime.to_iso8601(banned.banned_until)

    {:ok, lifted} = Accounts.unban_user(moderator, banned, "Appeal accepted")
    refute Accounts.banned?(lifted)
    assert Repo.exists?(from a in Action, where: a.action == "user.unban")
    assert Accounts.unban_user(moderator, lifted) == {:error, :not_banned}
  end

  @tag req: "MO-02"
  test "MO-02 a ban is for good or until a time, after which it no longer counts", %{
    moderator: moderator,
    user: user
  } do
    {:ok, {banned, _}} = Accounts.ban_user(moderator, user, nil)
    assert banned.banned_until == nil
    assert Accounts.banned?(banned, in_days(10_000))

    ended = %{banned | banned_until: in_days(-1)}
    refute Accounts.banned?(ended)
    assert Accounts.ban_user(moderator, user_fixture(), in_days(-1)) == {:error, :past}
  end

  @tag req: "MO-02"
  test "MO-02 owners and administrators are never banned; only server moderators ban", %{
    moderator: moderator,
    user: user
  } do
    for role <- [:owner, :administrator] do
      assert Accounts.ban_user(moderator, user_with_role_fixture(role), nil) ==
               {:error, :not_bannable}
    end

    assert Accounts.ban_user(moderator, moderator, nil) == {:error, :not_bannable}
    assert Accounts.ban_user(user_fixture(), user, nil) == {:error, :forbidden}

    # Moderating one category is not enough: bans are server-wide.
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, role} = Access.create_role(admin, %{"name" => unique_role_name("Helpers")})
    {:ok, _} = Access.set_permission(admin, role, general, :moderate, :allow)
    helper = user_fixture()
    :ok = Access.grant_role(helper, role)

    refute Access.server_moderator?(helper)
    assert Access.server_moderator?(moderator)
    assert Access.server_moderator?(admin)
    assert Accounts.ban_user(helper, user, nil) == {:error, :forbidden}
    assert Repo.aggregate(Action, :count) == 0
  end
end

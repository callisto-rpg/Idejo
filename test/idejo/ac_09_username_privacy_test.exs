# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AC09UsernamePrivacyTest do
  @moduledoc """
  AC-09 (steward decision, 2026-11-06): a username or display name never shows an email
  address. New accounts are never named after it; accounts named so before are renamed.
  """
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query
  import Idejo.AccountsFixtures

  alias Idejo.Accounts.{OIDC, User, UserIdentity, UsernamePrivacy}
  alias Idejo.Audit.Entry
  alias Idejo.FakeOIDCProvider
  alias Idejo.Repo

  @moduletag req: "AC-09"

  test "AC-09 a provider giving the email as preferred_username: the account is not named after it" do
    FakeOIDCProvider.start!()

    for {claims, username, display} <- [
          {%{"name" => "Jane Doe", "preferred_username" => "jane.doe@mail.test"}, "Jane_Doe",
           "Jane Doe"},
          {%{"preferred_username" => "jane.doe@mail.test"}, "member", "Member"},
          {%{"name" => "jane.doe@mail.test"}, "member", "Member"}
        ] do
      n = System.unique_integer([:positive])

      claims =
        Map.merge(claims, %{
          "iss" => OIDC.config()[:issuer],
          "sub" => "s-#{n}",
          "email" => "jane#{n}.doe@mail.test",
          "email_verified" => true
        })

      assert {:ok, %User{} = user, :new} = OIDC.sign_in(claims)
      assert user.username == username or String.starts_with?(user.username, username <> "_")
      assert user.display_name == display
      refute user.username =~ "jane#{n}"
      refute user.username =~ "mail"
    end
  end

  test "AC-09 accounts named after their email are renamed, with an audit entry" do
    named = fn email, username, display ->
      user = user_fixture(%{email: email, display_name: display})
      Repo.update_all(from(u in User, where: u.id == ^user.id), set: [username: username])

      Repo.insert!(%UserIdentity{
        user_id: user.id,
        issuer: "https://id.test",
        subject: "sub-#{username}"
      })

      user
    end

    jane = named.("jane.doe@mail.test", "jane_doe_mail_test", "Jane Doe")
    jim = named.("jim@mail.test", "jim_mail_test_42", "jim@mail.test")
    kept = named.("kim@mail.test", "kimberly", "Kim")
    # Not linked to a provider: chose its own name, whatever it looks like.
    local = user_fixture(%{email: "lou@mail.test"})
    Repo.update_all(from(u in User, where: u.id == ^local.id), set: [username: "lou_mail_test"])

    assert UsernamePrivacy.rename_all() == 2

    assert Repo.get!(User, jane.id).username == "Jane_Doe"
    assert %User{username: "member" <> _, display_name: "member" <> _} = Repo.get!(User, jim.id)
    assert Repo.get!(User, kept.id).username == "kimberly"
    assert Repo.get!(User, local.id).username == "lou_mail_test"

    renames = Repo.all(from e in Entry, where: e.change == "user.rename")
    assert length(renames) == 2
    assert Enum.any?(renames, &(&1.after == %{"username" => "Jane_Doe"} and is_nil(&1.admin_id)))

    # Run again, nothing left to do.
    assert UsernamePrivacy.rename_all() == 0
  end

  test "AC-09 from_email? matches only the email's own form" do
    assert UsernamePrivacy.from_email?("jane_doe_mail_test", "jane.doe@mail.test")
    assert UsernamePrivacy.from_email?("Jane_doe_mail_test_7", "jane.doe@mail.test")
    refute UsernamePrivacy.from_email?("jane_doe", "jane.doe@mail.test")
    refute UsernamePrivacy.from_email?("jane_doe_mail_test_x", "jane.doe@mail.test")
  end

  test "AC-09 mentions of a renamed account no longer show the old name" do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Idejo.Forum.create_category(admin, %{"name" => "General"})
    jane = user_fixture(%{email: "jane.doe@mail.test", display_name: "Jane Doe"})

    Repo.update_all(from(u in User, where: u.id == ^jane.id),
      set: [username: "jane_doe_mail_test"]
    )

    Repo.insert!(%UserIdentity{user_id: jane.id, issuer: "https://id.test", subject: "jane"})

    {:ok, topic} =
      Idejo.Forum.create_topic(admin, general, %{
        "title" => "Hello",
        "body" =>
          "Welcome @jane_doe_mail_test! Write to x@jane_doe_mail_test.org or @jane_doe_mail_test_2."
      })

    [message] = Idejo.Forum.list_messages(topic)
    assert message.body_html =~ ">@jane_doe_mail_test</a>"

    assert UsernamePrivacy.rename_all() == 1
    message = Repo.get!(Idejo.Messages.Message, message.id)

    assert message.body_md ==
             "Welcome @Jane_Doe! Write to x@jane_doe_mail_test.org or @jane_doe_mail_test_2."

    assert message.body_html =~ ~s(href="/u/#{jane.id}" rel="noopener noreferrer">@Jane_Doe</a>)
    refute message.body_html =~ ">@jane_doe_mail_test<"
  end
end

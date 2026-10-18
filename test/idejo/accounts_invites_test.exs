# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AccountsInvitesTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Accounts.Invite
  alias Idejo.Audit
  alias Idejo.Settings

  @invalid "is not valid, used or expired"

  describe "registration modes" do
    @tag req: "AC-02"
    test "AC-02 registration is open by default: anyone signs up without an invite" do
      assert Settings.get(:registration_mode) == "open"
      assert {:ok, _user} = Accounts.register_user(valid_user_attributes())
    end

    @tag req: "AC-02"
    test "AC-02 switching to invite-only is audited; other values are refused" do
      admin = invite_only!()
      assert Settings.get(:registration_mode) == "invite_only"

      assert [%{admin_id: admin_id, before: %{"registration_mode" => "open"}}] =
               Audit.list_entries() |> Enum.filter(&(&1.change == "settings.update"))

      assert admin_id == admin.id

      assert {:error, changeset} =
               Settings.update_settings(admin, %{"registration_mode" => "closed"})

      assert "is invalid" in errors_on(changeset).registration_mode
    end

    @tag req: "AC-02"
    test "AC-02 while open, an invite code is not needed and not used up" do
      invite = invite_fixture()

      assert {:ok, _} = Accounts.register_user(valid_user_attributes(invite_code: invite.code))
      assert Repo.reload!(invite).used_by == nil
    end
  end

  describe "invite-only sign-up" do
    setup do
      admin = invite_only!()
      %{admin: admin, invite: invite_fixture(admin)}
    end

    @tag req: "AC-02"
    test "AC-02 without an invite nobody can sign up" do
      for code <- [nil, "", "made-up"] do
        assert {:error, changeset} =
                 Accounts.register_user(valid_user_attributes(invite_code: code))

        assert @invalid in errors_on(changeset).invite_code
      end
    end

    @tag req: "AC-02"
    test "AC-02 a valid invite lets one person sign up and is then used", %{invite: invite} do
      assert {:ok, user} = Accounts.register_user(valid_user_attributes(invite_code: invite.code))

      invite = Repo.reload!(invite)
      assert invite.used_by == user.id
      assert %DateTime{} = invite.used_at
      assert Invite.status(invite, DateTime.utc_now()) == :used

      assert {:error, changeset} =
               Accounts.register_user(valid_user_attributes(invite_code: invite.code))

      assert @invalid in errors_on(changeset).invite_code
    end

    @tag req: "AC-02"
    test "AC-02 an expired invite is refused", %{invite: invite} do
      Repo.update_all(Invite,
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
      )

      assert {:error, changeset} =
               Accounts.register_user(valid_user_attributes(invite_code: invite.code))

      assert @invalid in errors_on(changeset).invite_code
      assert Invite.status(Repo.reload!(invite), DateTime.utc_now()) == :expired
    end

    @tag req: "AC-02"
    test "AC-02 a failed sign-up does not use the invite up", %{invite: invite} do
      taken = unconfirmed_user_fixture()

      assert {:error, changeset} =
               Accounts.register_user(
                 valid_user_attributes(email: taken.email, invite_code: invite.code)
               )

      assert "has already been taken" in errors_on(changeset).email
      assert Repo.reload!(invite).used_by == nil
    end

    @tag req: "AC-02"
    test "AC-02 the invite error shows together with other errors" do
      assert {:error, changeset} =
               Accounts.register_user(valid_user_attributes(password: "short", invite_code: "x"))

      errors = errors_on(changeset)
      assert @invalid in errors.invite_code
      assert "should be at least 12 character(s)" in errors.password
    end

    @tag req: "AC-02"
    test "AC-02 the first-run owner needs no invite" do
      assert {:ok, _owner} =
               Accounts.register_user(valid_user_attributes(), confirmed: true, skip_invite: true)
    end
  end

  describe "invites" do
    @tag req: "AC-02"
    test "AC-02 an invite is single-use, random and valid for 7 days" do
      admin = user_with_role_fixture(:administrator)
      {:ok, invite} = Accounts.create_invite(admin)
      {:ok, other} = Accounts.create_invite(admin)

      assert invite.created_by == admin.id
      assert invite.used_by == nil
      assert byte_size(invite.code) >= 20
      assert invite.code != other.code

      days = DateTime.diff(invite.expires_at, DateTime.utc_now(), :second) / 86_400
      assert_in_delta days, 7, 0.001
    end

    @tag req: "AC-02"
    test "AC-02 creating an invite is audited without the full code" do
      admin = user_with_role_fixture(:administrator)
      {:ok, invite} = Accounts.create_invite(admin)

      assert [%{change: "invite.create", admin_id: admin_id, after: after_}] =
               Audit.list_entries()

      assert admin_id == admin.id
      assert after_["code_start"] == String.slice(invite.code, 0, 4)
      refute inspect(after_) =~ invite.code
    end

    @tag req: "AC-02"
    test "AC-02 invites are listed newest first with creator and user" do
      admin = invite_only!()
      first = invite_fixture(admin)
      Repo.update_all(Invite, set: [created_at: DateTime.add(DateTime.utc_now(:second), -60)])
      second = invite_fixture(admin)
      {:ok, user} = Accounts.register_user(valid_user_attributes(invite_code: first.code))

      assert [%Invite{code: c2, user: nil}, %Invite{code: c1, user: used_by, creator: creator}] =
               Accounts.list_invites()

      assert {c2, c1} == {second.code, first.code}
      assert used_by.id == user.id
      assert creator.id == admin.id
    end
  end
end

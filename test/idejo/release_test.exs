# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ReleaseTest do
  # Not async: one test points :uploads_dir elsewhere, which the uploads tests read.
  use Idejo.DataCase, async: false

  import ExUnit.CaptureIO
  import Idejo.AccountsFixtures

  alias Idejo.Accounts
  alias Idejo.Accounts.UserToken
  alias Idejo.Audit
  alias Idejo.Release

  describe "reset_owner_password!/1" do
    @tag req: "AD-09"
    test "AD-09 gives the only owner a new password and ends their sessions" do
      owner = user_with_role_fixture(:owner, %{password: "the old passphrase"})
      user_with_role_fixture(:administrator)
      token = Accounts.generate_user_session_token(owner)
      socket_id = Accounts.session_socket_id(token)
      IdejoWeb.Endpoint.subscribe(IdejoWeb.UserAuth.live_socket_id(socket_id))

      assert {:ok, {reset, password}} = Release.reset_owner_password!(nil)

      assert reset.id == owner.id
      assert String.length(password) >= 24
      assert Accounts.get_user_by_email_and_password(owner.email, password)
      refute Accounts.get_user_by_email_and_password(owner.email, "the old passphrase")
      refute Accounts.get_user_by_session_token(token)
      refute Repo.exists?(from t in UserToken, where: t.user_id == ^owner.id)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

      assert [%{change: "user.password_reset", admin_id: nil, after: after_} | _] =
               Audit.list_entries()

      assert after_ == %{"user" => owner.username}
      refute inspect(Audit.list_entries()) =~ password
    end

    @tag req: "AD-09"
    test "AD-09 with several owners, one must be named, ignoring case" do
      first = user_with_role_fixture(:owner, %{username: unique_username("ann")})
      second = user_with_role_fixture(:owner, %{username: unique_username("bob")})

      assert {:error, {:several_owners, names}} = Release.reset_owner_password!(nil)
      assert Enum.sort(names) == Enum.sort([first.username, second.username])

      assert {:ok, {reset, password}} =
               Release.reset_owner_password!(String.upcase(second.username))

      assert reset.id == second.id
      assert Accounts.get_user_by_email_and_password(second.email, password)
    end

    @tag req: "AD-09"
    test "AD-09 resets only an owner's password" do
      user_with_role_fixture(:owner)
      admin = user_with_role_fixture(:administrator)

      assert Release.reset_owner_password!(admin.username) == {:error, :not_an_owner}
      assert Release.reset_owner_password!("nobody_here") == {:error, :not_an_owner}
      assert Audit.list_entries() == []
    end

    @tag req: "AD-09"
    test "AD-09 without an owner, points to the setup wizard" do
      assert Release.reset_owner_password!(nil) == {:error, :no_owner}

      output =
        capture_io(fn ->
          assert catch_exit(Release.reset_owner_password("")) == {:shutdown, 1}
        end)

      assert output =~ "setup wizard"
    end
  end

  describe "reset_owner_password/1" do
    @tag req: "AD-09"
    test "AD-09 prints the new password once" do
      owner = user_with_role_fixture(:owner)

      output = capture_io(fn -> assert Release.reset_owner_password(owner.username) == :ok end)

      [password] = Regex.run(~r/^    (\S+)$/m, output, capture: :all_but_first)
      assert Accounts.get_user_by_email_and_password(owner.email, password)
      assert output =~ owner.email
    end
  end

  describe "health" do
    @tag req: "AD-09"
    test "AD-09 checks the server, database, migrations, owner and uploads" do
      checks = Release.health_checks()

      assert Enum.map(checks, &elem(&1, 0)) ==
               ~w(server database migrations owner uploads)

      assert {"owner", :warning, _} = List.keyfind(checks, "owner", 0)
      assert Enum.all?(checks, &(elem(&1, 1) in [:ok, :warning]))

      user_with_role_fixture(:owner)
      assert {"owner", :ok, _} = List.keyfind(Release.health_checks(), "owner", 0)

      output = capture_io(fn -> assert Release.health() == :ok end)
      assert output =~ ~r/ok\s+database\s+reachable/
    end

    @tag req: "AD-09"
    test "AD-09 fails when the uploads directory is not writable" do
      dir = Application.fetch_env!(:idejo, :uploads_dir)
      File.mkdir_p!(dir)
      # A directory under a plain file can be neither made nor written.
      file = Path.join(dir, "not-a-directory-#{System.unique_integer([:positive])}")
      File.write!(file, "")
      Application.put_env(:idejo, :uploads_dir, Path.join(file, "uploads"))
      on_exit(fn -> Application.put_env(:idejo, :uploads_dir, dir) end)

      assert {"uploads", :error, detail} = List.keyfind(Release.health_checks(), "uploads", 0)
      assert detail =~ "not writable"

      output = capture_io(fn -> assert catch_exit(Release.health()) == {:shutdown, 1} end)
      assert output =~ "Some checks failed."
    end
  end
end

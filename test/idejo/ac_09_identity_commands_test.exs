# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AC09IdentityCommandsTest do
  @moduledoc """
  AC-09, for a shared identity provider (idejo Hub): delete or leave by the provider's subject,
  from the command line (`delete-account`, `leave`).
  """
  # Not async: the provider's configuration is global.
  use Idejo.DataCase, async: false

  import ExUnit.CaptureIO
  import Idejo.AccountsFixtures

  alias Idejo.{Accounts, Audit, Forum, Release, Repo}
  alias Idejo.Accounts.OIDC
  alias Idejo.Notifications.{Digest, EmailPreference}

  @issuer "https://id.idejo.test"

  setup do
    original = Application.get_env(:idejo, :oidc)

    Application.put_env(:idejo, :oidc,
      issuer: @issuer,
      client_id: "c",
      client_secret: "s",
      label: "idejo ID"
    )

    on_exit(fn -> Application.put_env(:idejo, :oidc, original) end)

    user = user_fixture()
    {:ok, _} = OIDC.link(user, %{"iss" => @issuer, "sub" => "sub-#{user.id}"})
    %{user: user, subject: "sub-#{user.id}"}
  end

  defp exit_code(fun) do
    capture_io(fn -> send(self(), {:result, catch_exit(fun.())}) end)
    receive do: ({:result, {:shutdown, code}} -> code)
  end

  describe "delete-account" do
    @tag req: "AC-09"
    test "AC-09 deletes the linked account as AC-07 does; its messages stay as Deleted user",
         %{user: user, subject: subject} do
      admin = user_with_role_fixture(:administrator)
      {:ok, category} = Forum.create_category(admin, %{"name" => "Talk"})

      {:ok, topic} =
        Forum.create_topic(user, category, %{"title" => "Mine", "body" => "Written by them"})

      token = Accounts.generate_user_session_token(user)

      assert {:ok, {deleted, _socket_ids}} = Accounts.delete_user_by_identity(subject)
      assert deleted.status == "deleted"
      assert deleted.display_name == "Deleted user"
      refute Accounts.get_user_by_session_token(token)
      refute OIDC.find_user(%{"iss" => @issuer, "sub" => subject})
      # The topic and its first message stay, by the anonymised account.
      assert Repo.get!(Idejo.Forum.Topic, topic.id)
      assert [%{change: "user.delete_by_identity", admin_id: nil} | _] = Audit.list_entries()

      assert Accounts.delete_user_by_identity(subject) == {:error, :not_found}
    end

    @tag req: "AC-09"
    test "AC-09 refuses the last owner and an unknown subject" do
      owner = user_with_role_fixture(:owner)
      {:ok, _} = OIDC.link(owner, %{"iss" => @issuer, "sub" => "owner-sub"})
      assert Accounts.delete_user_by_identity("owner-sub") == {:error, :last_owner}
      assert Accounts.delete_user_by_identity("nobody") == {:error, :not_found}
    end

    @tag req: "AC-09"
    test "AC-09 the command exits 0 when done, 2 when nothing is linked, 1 without a provider",
         %{subject: subject} do
      output = capture_io(fn -> assert Release.delete_account(subject) == :ok end)
      assert output =~ "deleted"
      assert exit_code(fn -> Release.delete_account(subject) end) == 2

      Application.put_env(:idejo, :oidc, nil)
      assert exit_code(fn -> Release.delete_account("x") end) == 1
    end
  end

  describe "leave" do
    @tag req: "AC-09"
    test "AC-09 ends sessions, pushes and email summaries, and keeps the account and its link",
         %{user: user, subject: subject} do
      token = Accounts.generate_user_session_token(user)
      {:ok, _} = Digest.update_preferences(user, %{mentions_and_replies: true})

      output = capture_io(fn -> assert Release.leave(subject) == :ok end)
      assert output =~ "Left"

      refute Accounts.get_user_by_session_token(token)
      prefs = Digest.preferences(user)
      assert Enum.all?(EmailPreference.options(), &(Map.get(prefs, &1) == false))

      # Coming back with the same identity finds the same, active account.
      kept = OIDC.find_user(%{"iss" => @issuer, "sub" => subject})
      assert kept.id == user.id
      assert kept.status == "active"
      assert [%{change: "user.leave"} | _] = Audit.list_entries()
      assert exit_code(fn -> Release.leave("nobody") end) == 2
    end
  end
end

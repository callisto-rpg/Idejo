# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.MemoTest do
  # Sets server-wide settings.
  use Idejo.DataCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Memo
  alias Idejo.Settings

  # The queries this process sends while `fun` runs.
  defp queries(fun) do
    me = self()
    handler = "memo-test-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      [:idejo, :repo, :query],
      fn _, _, _, _ -> if self() == me, do: send(me, :query) end,
      nil
    )

    fun.()
    :telemetry.detach(handler)
    count(0)
  end

  defp count(n) do
    receive do
      :query -> count(n + 1)
    after
      0 -> n
    end
  end

  @tag req: "NF-04"
  test "NF-04 while on, roles, permission checks and settings are read once" do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture()

    check = fn ->
      Access.roles_of(member)
      Access.can?(member, :post, general)
      Access.can?(member, :post, general)
      Access.administrator?(member)
      Settings.get(:server_name)
      Settings.get(:gm_window_seconds)
    end

    off = queries(check)
    assert off >= 6
    refute Memo.on?()

    # Once to fill it, then nothing more.
    assert Memo.run(fn -> queries(check) + queries(check) end) == 4
    refute Memo.on?()
  end

  @tag req: "NF-04"
  test "NF-04 a change of roles, permissions or settings is read fresh in the same run" do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    member = user_fixture()
    moderator = Access.built_in_role!(:moderator)

    Memo.run(fn ->
      refute Access.can?(member, :moderate, general)
      :ok = Access.grant_role(member, moderator)
      assert Access.can?(member, :moderate, general)

      assert Settings.get(:server_name) != "Memo Garden"
      {:ok, _} = Settings.update_settings(admin, %{"server_name" => "Memo Garden"})
      assert Settings.get(:server_name) == "Memo Garden"

      {:ok, _} = Access.set_permission(admin, moderator, general, :moderate, :deny)
      refute Access.can?(member, :moderate, general)
    end)
  end

  @tag req: "NF-04"
  test "NF-04 the memo starts empty each time and is off outside a run" do
    Memo.start()
    assert Memo.fetch(:a, fn -> 1 end) == 1
    assert Memo.fetch(:a, fn -> 2 end) == 1
    Memo.start()
    assert Memo.fetch(:a, fn -> 3 end) == 3
    Memo.stop()
    assert Memo.fetch(:a, fn -> 4 end) == 4

    # A run inside a run goes on with what the outer one read.
    Memo.run(fn ->
      Memo.fetch(:b, fn -> 1 end)
      Memo.run(fn -> assert Memo.fetch(:b, fn -> 2 end) == 1 end)
      assert Memo.on?()
    end)

    refute Memo.on?()
  end
end

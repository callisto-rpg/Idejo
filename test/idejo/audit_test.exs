# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.AuditTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Audit
  alias Idejo.Audit.Entry

  setup do
    %{admin: user_fixture()}
  end

  describe "record/4" do
    @tag req: "SP-06"
    test "SP-06 records the admin, the change, the values before and after, and the time", %{
      admin: admin
    } do
      assert {:ok, entry} =
               Audit.record(admin, "settings.update", %{"name" => "Old"}, %{"name" => "New"})

      entry = Repo.reload!(entry)
      assert entry.admin_id == admin.id
      assert entry.change == "settings.update"
      assert entry.before == %{"name" => "Old"}
      assert entry.after == %{"name" => "New"}
      assert %DateTime{} = entry.created_at
    end

    @tag req: "SP-06"
    test "SP-06 before is empty for something new and after for something removed", %{
      admin: admin
    } do
      assert {:ok, %Entry{before: nil}} = Audit.record(admin, "role.create", nil, %{"n" => 1})
      assert {:ok, %Entry{after: nil}} = Audit.record(admin, "role.delete", %{"n" => 1}, nil)
    end

    @tag req: "SP-06"
    test "SP-06 command-line changes are recorded without an admin" do
      assert {:ok, %Entry{admin_id: nil}} = Audit.record(nil, "settings.update", nil, %{})
    end

    @tag req: "SP-06"
    test "SP-06 the change must name a subject and an action", %{admin: admin} do
      for bad <- ["", "settings", "Settings.Update", "settings.update.now", "role create"] do
        assert {:error, changeset} = Audit.record(admin, bad, nil, nil)
        assert errors_on(changeset).change != []
      end
    end

    @tag req: "SP-06"
    test "SP-06 an entry is rolled back with the change it records", %{admin: admin} do
      assert {:error, :change_failed} =
               Repo.transact(fn ->
                 {:ok, _} = Audit.record(admin, "role.create", nil, %{"name" => "team"})
                 {:error, :change_failed}
               end)

      assert Audit.list_entries() == []
    end
  end

  describe "append-only" do
    setup %{admin: admin} do
      {:ok, entry} = Audit.record(admin, "role.update", %{"a" => 1}, %{"a" => 2})
      %{entry: entry}
    end

    @tag req: "SP-06"
    test "SP-06 entries cannot be changed", %{entry: entry} do
      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        entry |> Ecto.Changeset.change(change: "role.delete") |> Repo.update()
      end

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.update_all(Entry, set: [after: %{}])
      end
    end

    @tag req: "SP-06"
    test "SP-06 entries cannot be deleted", %{entry: entry} do
      assert_raise Postgrex.Error, ~r/append-only/, fn -> Repo.delete(entry) end
      assert_raise Postgrex.Error, ~r/append-only/, fn -> Repo.delete_all(Entry) end
      assert_raise Postgrex.Error, ~r/append-only/, fn -> Repo.query!("TRUNCATE audit_log") end
    end
  end

  describe "list_entries/1" do
    @tag req: "SP-06"
    test "SP-06 lists entries newest first with their admin", %{admin: admin} do
      {:ok, first} = Audit.record(admin, "role.create", nil, %{})
      {:ok, second} = Audit.record(nil, "settings.update", nil, %{})

      assert [%Entry{id: id2, admin: nil}, %Entry{id: id1, admin: %{id: admin_id}}] =
               Audit.list_entries()

      assert {id2, id1, admin_id} == {second.id, first.id, admin.id}
      assert [%Entry{id: ^id2}] = Audit.list_entries(limit: 1)
    end
  end

  describe "snapshot/2" do
    @tag req: "SP-06"
    test "SP-06 takes only the named fields, with string keys" do
      assert Audit.snapshot(%{name: "Team", colour: "#123456", secret: "x"}, [:name, :colour]) ==
               %{"name" => "Team", "colour" => "#123456"}
    end
  end
end

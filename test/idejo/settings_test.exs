# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.SettingsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Audit
  alias Idejo.Settings

  setup do
    %{admin: user_with_role_fixture(:administrator)}
  end

  @tag req: "AD-02"
  test "AD-02 a setting that was never saved has its default" do
    assert Settings.get(:server_name) == "Idejo"
    assert %{server_name: "Idejo"} = Settings.all()
  end

  @tag req: "AD-02"
  test "AD-02 saving a setting stores it and records the change", %{admin: admin} do
    assert {:ok, %{server_name: "Lumière"}} =
             Settings.update_settings(admin, %{"server_name" => "  Lumière  "})

    assert Settings.get(:server_name) == "Lumière"

    assert [entry] = Audit.list_entries()
    assert entry.admin_id == admin.id
    assert entry.change == "settings.update"
    assert entry.before == %{"server_name" => "Idejo"}
    assert entry.after == %{"server_name" => "Lumière"}
  end

  @tag req: "AD-02"
  test "AD-02 saving again overwrites and audits the old value", %{admin: admin} do
    {:ok, _} = Settings.update_settings(admin, %{"server_name" => "One"})
    {:ok, _} = Settings.update_settings(admin, %{"server_name" => "Two"})

    assert Settings.get(:server_name) == "Two"

    assert [%{before: %{"server_name" => "One"}, after: %{"server_name" => "Two"}} | _] =
             Audit.list_entries()
  end

  @tag req: "AD-02"
  test "AD-02 the website theme has the steward's colours until changed", %{admin: admin} do
    assert Settings.theme() == %{
             primary: "#daa304ff",
             secondary: "#f2c94c",
             tertiary: "#b8860b",
             light_bg: "#fdfcf6",
             dark_bg: "#1d1a00"
           }

    assert {:ok, _} =
             Settings.update_settings(admin, %{
               "theme_primary" => " #3366FF ",
               "theme_dark_bg" => "#11223380"
             })

    assert %{primary: "#3366ff", dark_bg: "#11223380", secondary: "#f2c94c"} = Settings.theme()

    for bad <- ["red", "#12345", "#1234567", "##b8860b", "#ggg000", "#fff;}"] do
      assert {:error, changeset} = Settings.update_settings(admin, %{"theme_tertiary" => bad})
      assert ["must look like #daa304 or #daa304ff"] = errors_on(changeset).theme_tertiary
    end

    assert Settings.theme().tertiary == "#b8860b"
  end

  @tag req: "AD-02"
  test "AD-02 saving unchanged values writes nothing", %{admin: admin} do
    # The push keys (PN-14) are rows of their own, made by a migration.
    stored = Repo.aggregate(Idejo.Settings.Setting, :count)
    assert {:ok, _} = Settings.update_settings(admin, %{"server_name" => "Idejo"})
    assert Audit.list_entries() == []
    assert Repo.aggregate(Idejo.Settings.Setting, :count) == stored
  end

  @tag req: "AD-02"
  test "AD-02 invalid values are rejected and nothing is written", %{admin: admin} do
    assert {:error, changeset} = Settings.update_settings(admin, %{"server_name" => "  "})
    assert "can't be blank" in errors_on(changeset).server_name

    long = String.duplicate("x", 81)
    assert {:error, changeset} = Settings.update_settings(admin, %{"server_name" => long})
    assert "should be at most 80 character(s)" in errors_on(changeset).server_name

    assert Settings.get(:server_name) == "Idejo"
    assert Audit.list_entries() == []
  end

  @tag req: "AD-02"
  test "AD-02 unknown keys are ignored", %{admin: admin} do
    assert {:ok, settings} = Settings.update_settings(admin, %{"evil" => "1"})
    refute Map.has_key?(settings, :evil)
    assert Audit.list_entries() == []
  end
end

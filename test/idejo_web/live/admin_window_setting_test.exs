# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.AdminWindowSettingTest do
  use IdejoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Idejo.AccountsFixtures

  alias Idejo.Audit
  alias Idejo.Forum
  alias Idejo.Messages
  alias Idejo.Settings

  setup %{conn: conn} do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})

    {:ok, topic} =
      Forum.create_topic(user_fixture(), general, %{"title" => "Chat", "body" => "Hi"})

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    %{conn: log_in_user(conn, admin), admin: admin, topic: topic}
  end

  defp settings_entries, do: Enum.filter(Audit.list_entries(), &(&1.change == "settings.update"))

  defp window(message), do: DateTime.diff(message.closes_at, message.opened_at)

  @tag req: "AD-04"
  test "AD-04 an administrator sets the window in Admin → Settings, audited", %{
    conn: conn,
    admin: admin
  } do
    {:ok, lv, html} = live(conn, ~p"/admin")
    assert html =~ "Growing-message window (seconds)"

    assert has_element?(
             lv,
             ~s(#settings-form input[name="settings[gm_window_seconds]"][value="15"])
           )

    assert lv
           |> form("#settings-form", settings: %{gm_window_seconds: "90"})
           |> render_submit() =~ "Settings saved."

    assert Settings.get(:gm_window_seconds) == 90

    assert [%{admin_id: admin_id, before: before, after: after_}] = settings_entries()

    assert admin_id == admin.id
    assert before == %{"gm_window_seconds" => 15}
    assert after_ == %{"gm_window_seconds" => 90}
  end

  @tag req: "AD-04"
  test "AD-04 a window out of range or blank is refused", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin")

    for {value, error} <- [
          {"1", "must be greater than or equal to 2"},
          {"601", "must be less than or equal to 600"},
          {"", "is invalid"}
        ] do
      html =
        lv |> form("#settings-form", settings: %{gm_window_seconds: value}) |> render_submit()

      refute html =~ "Settings saved."
      assert has_element?(lv, "#settings-form p.text-error", error)
    end

    assert Settings.get(:gm_window_seconds) == 15
    assert settings_entries() == []
  end

  @tag req: "GM-15"
  test "GM-15 the server-wide window applies to messages opened after the change", %{
    admin: admin,
    topic: topic
  } do
    early = user_fixture()
    {:ok, before} = Messages.commit(early, topic, "Opened under 15 s")
    assert window(before) == 15

    {:ok, _} = Settings.update_settings(admin, %{"gm_window_seconds" => "120"})

    {:ok, late} = Messages.commit(user_fixture(), topic, "Opened under 120 s")
    assert window(late) == 120

    # An open message keeps the window fixed at its first commit (GM-03).
    {:ok, appended} = Messages.commit(early, topic, "Opened under 15 s. Still going")
    assert appended.id == before.id
    assert appended.closes_at == before.closes_at
  end
end

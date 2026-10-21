# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.ModerationReportsTest do
  use Idejo.DataCase, async: true

  import Idejo.AccountsFixtures

  alias Idejo.Access
  alias Idejo.Forum
  alias Idejo.Moderation
  alias Idejo.Moderation.{Action, Report}

  setup do
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, help} = Forum.create_category(admin, %{"name" => "Help"})
    author = user_fixture()
    {:ok, topic} = Forum.create_topic(author, general, %{"title" => "T", "body" => "Rude words"})
    {:ok, help_topic} = Forum.create_topic(author, help, %{"title" => "H", "body" => "Spam link"})
    [message] = Forum.list_messages(topic)
    [help_message] = Forum.list_messages(help_topic)

    %{
      admin: admin,
      general: general,
      author: author,
      message: message,
      help_message: help_message
    }
  end

  defp moderator_of(admin, category) do
    {:ok, role} =
      Access.create_role(admin, %{"name" => "Mods #{System.unique_integer([:positive])}"})

    {:ok, _} = Access.set_permission(admin, role, category, :moderate, :allow)
    user = user_fixture()
    :ok = Access.grant_role(user, role)
    user
  end

  @tag req: "MO-01"
  test "MO-01 a member reports a message with a reason, once", %{author: author, message: message} do
    reporter = user_fixture()

    assert {:ok, %Report{status: "open", reason: "Insults"}} =
             Moderation.report_message(reporter, message, %{"reason" => "  Insults "})

    assert {:error, changeset} =
             Moderation.report_message(reporter, message, %{"reason" => "Again"})

    assert "you have already reported this message" in errors_on(changeset).message_id

    assert {:error, changeset} =
             Moderation.report_message(user_fixture(), message, %{"reason" => " "})

    assert "can't be blank" in errors_on(changeset).reason

    assert Moderation.report_message(author, message, %{"reason" => "Mine"}) ==
             {:error, :forbidden}
  end

  @tag req: "MO-01"
  test "MO-01 reports go to the moderators of the category, grouped by message", %{
    admin: admin,
    general: general,
    message: message,
    help_message: help_message
  } do
    for reason <- ["Insults", "Rude"],
        do: {:ok, _} = Moderation.report_message(user_fixture(), message, %{"reason" => reason})

    {:ok, _} = Moderation.report_message(user_fixture(), help_message, %{"reason" => "Spam"})

    general_mod = moderator_of(admin, general)
    assert [%{message: %{id: id}, reports: reports}] = Moderation.list_open_reports(general_mod)
    assert id == message.id
    assert Enum.map(reports, & &1.reason) == ["Insults", "Rude"]
    assert Moderation.open_report_count(general_mod) == 1

    assert length(Moderation.list_open_reports(admin)) == 2
    assert Moderation.open_report_count(admin) == 2
    assert Moderation.list_open_reports(user_fixture()) == []
  end

  @tag req: "MO-01"
  test "MO-01 resolving or dismissing closes all of a message's reports, logged", %{
    admin: admin,
    general: general,
    message: message,
    help_message: help_message
  } do
    for r <- ["A", "B"],
        do: {:ok, _} = Moderation.report_message(user_fixture(), message, %{"reason" => r})

    general_mod = moderator_of(admin, general)

    assert Moderation.handle_reports(general_mod, help_message, :resolve) == {:error, :forbidden}

    assert {:ok, 2} =
             Moderation.handle_reports(general_mod, message, :resolve, "Warned the author")

    assert Repo.all(from r in Report, select: {r.status, r.handled_by_id}) == [
             {"resolved", general_mod.id},
             {"resolved", general_mod.id}
           ]

    entry = Repo.one!(Action)

    assert {entry.action, entry.reason, entry.details} ==
             {"report.resolve", "Warned the author", %{"reports" => 2}}

    assert Moderation.handle_reports(general_mod, message, :dismiss) == {:error, :no_reports}

    # A new report after handling opens again.
    {:ok, _} = Moderation.report_message(user_fixture(), message, %{"reason" => "Still rude"})
    assert {:ok, 1} = Moderation.handle_reports(admin, message, :dismiss)
  end
end

# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AP13ModerationTest do
  @moduledoc """
  AP-13: every moderation action of the web app through the API, to moderators of the
  category, with the same context functions (and so the same log entries, MO-03); a member
  who may see the topic but not moderate it gets 403.
  """
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query
  import Idejo.AccountsFixtures
  import Idejo.ImageFixtures
  import IdejoWeb.ApiHelpers

  alias Idejo.{Accounts, Forum, Messages, Moderation, Repo}
  alias Idejo.Forum.{Topic, TopicIcons}
  alias Idejo.Messages.Message
  alias Idejo.Moderation.{Action, Report}

  setup do
    world = IdejoWeb.ApiWorld.build()
    moderator = user_with_role_fixture(:moderator)
    {mod_token, _} = api_token_fixture(moderator)
    {member_token, _} = api_token_fixture(world.member)
    {admin_api, _} = api_token_fixture(world.admin)

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    Map.merge(world, %{
      moderator: moderator,
      mod: mod_token,
      member_token: member_token,
      admin_api: admin_api
    })
  end

  defp api(token, method, path, body \\ %{}),
    do:
      build_conn() |> api_conn(token) |> Phoenix.ConnTest.dispatch(@endpoint, method, path, body)

  defp logged?(action), do: Repo.exists?(from a in Action, where: a.action == ^action)

  @tag req: "AP-13"
  test "AP-13 a member may not moderate what they can see: 403", ctx do
    for {method, path} <- [
          {:post, "/api/v1/topics/#{ctx.topic.id}/lock"},
          {:post, "/api/v1/topics/#{ctx.topic.id}/archive"},
          {:delete, "/api/v1/moderation/messages/#{ctx.message.id}"},
          {:post, "/api/v1/moderation/messages/#{ctx.message.id}/close"}
        ] do
      assert api(ctx.member_token, method, path) |> api_json(403) |> get_in(["error", "code"]) ==
               "forbidden"
    end

    assert api(ctx.member_token, :get, "/api/v1/topics/#{ctx.topic.id}/moderation")
           |> api_json(404)
  end

  @tag req: "AP-13"
  test "AP-13 reports: listed with reporters for moderators, resolved and dismissed", ctx do
    {:ok, _} = Moderation.report_message(ctx.member, ctx.message, %{"reason" => "Rude"})
    [group] = api(ctx.mod, :get, "/api/v1/moderation/reports") |> api_json(200) |> Map.get("data")
    assert group["message"]["id"] == ctx.message.id
    assert [%{"reason" => "Rude", "reporter" => %{"id" => reporter}}] = group["reports"]
    assert reporter == ctx.member.id

    assert api(ctx.mod, :patch, "/api/v1/moderation/reports/#{ctx.message.id}", %{
             "outcome" => "resolve",
             "note" => "Talked"
           })
           |> api_json(204)

    assert Repo.all(from r in Report, select: r.status) == ["resolved"]
    assert logged?("report.resolve")
    assert api(ctx.mod, :get, "/api/v1/moderation/reports") |> api_json(200) == %{"data" => []}
  end

  @tag req: "AP-13"
  test "AP-13 topics: lock, pin, rename, move, archive, unarchive, inactive, delete", ctx do
    {:ok, elsewhere} = Forum.create_category(ctx.admin, %{"name" => "Elsewhere"})
    path = "/api/v1/topics/#{ctx.topic.id}"

    assert api(ctx.mod, :post, path <> "/lock", %{"reason" => "Heated"})
           |> api_json(200)
           |> Map.get("locked")

    refute api(ctx.mod, :post, path <> "/unlock") |> api_json(200) |> Map.get("locked")
    assert api(ctx.mod, :post, path <> "/pin") |> api_json(200) |> Map.get("pinned")
    refute api(ctx.mod, :post, path <> "/unpin") |> api_json(200) |> Map.get("pinned")

    assert api(ctx.mod, :patch, path, %{"title" => "Renamed", "reason" => "Clearer"})
           |> api_json(200)
           |> Map.get("title") == "Renamed"

    assert logged?("topic.rename")

    menu = api(ctx.mod, :get, path <> "/moderation") |> api_json(200)
    assert Enum.any?(menu["move_targets"], &(&1["id"] == elsewhere.id))

    assert api(ctx.mod, :post, path <> "/move", %{"category_id" => elsewhere.id})
           |> api_json(200)
           |> Map.get("category_id") == elsewhere.id

    assert api(ctx.mod, :post, path <> "/move", %{"category_id" => Ecto.UUID.generate()})
           |> api_json(422)

    assert api(ctx.mod, :post, path <> "/mark-inactive") |> api_json(200)
    assert logged?("topic.inactive")

    assert api(ctx.admin_api, :post, path <> "/archive") |> api_json(200) |> Map.get("archived")
    unarchived = api(ctx.admin_api, :post, path <> "/unarchive") |> api_json(200)
    refute unarchived["archived"]
    assert unarchived["category_id"] == elsewhere.id

    assert api(ctx.mod, :delete, path, %{"confirm" => false}) |> api_json(422)
    assert api(ctx.mod, :delete, path, %{"confirm" => true, "reason" => "Gone"}) |> api_json(204)
    refute Repo.get(Topic, ctx.topic.id)
    assert logged?("topic.delete")
  end

  @tag req: "AP-13"
  test "AP-13 message pins (steward request, 2026-11-13): moderators pin, everyone lists", ctx do
    pin = "/api/v1/messages/#{ctx.message.id}/pin"
    pins = "/api/v1/topics/#{ctx.topic.id}/pins"

    assert api(ctx.member_token, :put, pin) |> api_json(403)
    assert api(ctx.mod, :put, pin) |> api_json(200) |> Map.get("pinned_at")
    assert logged?("message.pin")

    listed = api(ctx.member_token, :get, pins) |> api_json(200)
    assert Enum.map(listed["data"], & &1["id"]) == [ctx.message.id]

    assert api(ctx.mod, :delete, pin) |> api_json(200) |> Map.get("pinned_at") == nil
    assert logged?("message.unpin")
    assert api(ctx.member_token, :get, pins) |> api_json(200) == %{"data" => []}
  end

  @tag req: "AP-13"
  test "AP-13 topic permissions (steward request, 2026-11-13): read and set by moderators",
       ctx do
    path = "/api/v1/topics/#{ctx.topic.id}/permissions"
    assert api(ctx.member_token, :get, path) |> api_json(403)

    before = api(ctx.mod, :get, path) |> api_json(200)
    assert before["topic_id"] == ctx.topic.id
    refute Enum.any?(before["roles"], &(&1["name"] in ~w(owner administrator)))
    member = Enum.find(before["roles"], &(&1["name"] == "member"))
    assert member["own"]["post"] == "unset"
    assert is_boolean(member["category"]["post"])

    settings = %{"settings" => %{member["id"] => %{"post" => "deny", "nonsense" => "allow"}}}
    after_put = api(ctx.mod, :put, path, settings) |> api_json(200)
    assert Enum.find(after_put["roles"], &(&1["id"] == member["id"]))["own"]["post"] == "deny"
    assert logged?("topic.permission")
  end

  @tag req: "AP-13"
  test "AP-13 followed by everyone, for administrators only", ctx do
    path = "/api/v1/topics/#{ctx.topic.id}/followed-by-everyone"
    assert api(ctx.mod, :put, path) |> api_json(403)
    {admin, _} = api_token_fixture(ctx.admin)
    assert api(admin, :put, path) |> api_json(200) |> Map.get("followed_by_everyone")
    refute api(admin, :delete, path) |> api_json(200) |> Map.get("followed_by_everyone")
  end

  @tag req: "AP-13"
  test "AP-13 icons and topical topics", ctx do
    {:ok, star} = TopicIcons.create(ctx.admin, image_file(:png), %{"name" => "Star"})

    [%{"id" => id}] =
      api(ctx.mod, :get, "/api/v1/topic-icons") |> api_json(200) |> Map.get("data")

    assert id == star.id

    topical =
      api(ctx.mod, :post, "/api/v1/topics/#{ctx.topic.id}/make-topical", %{"icon_id" => star.id})
      |> api_json(200)

    assert topical["icon"] =~ "/uploads/"

    assert api(ctx.mod, :put, "/api/v1/topics/#{ctx.topic.id}/icon", %{"icon_id" => nil})
           |> api_json(200)
           |> Map.get("icon") == nil
  end

  @tag req: "AP-13"
  test "AP-13 messages: close, edit, delete, delete several, move", ctx do
    {:ok, open} = Messages.commit(ctx.other, ctx.topic, "Still writing")

    closed =
      api(ctx.mod, :post, "/api/v1/moderation/messages/#{open.id}/close", %{
        "reason" => "Off topic"
      })
      |> api_json(200)

    assert closed["state"] == "closed"
    assert logged?("message.close")

    edited =
      api(ctx.mod, :put, "/api/v1/moderation/messages/#{ctx.message.id}", %{
        "body_md" => "Fixed",
        "reason" => "Personal data"
      })
      |> api_json(200)

    assert edited["moderator_edited"] and edited["body_md"] == "Fixed"

    assert [%{"body_md" => "Tomatoes"}] =
             api(ctx.mod, :get, "/api/v1/messages/#{ctx.message.id}/versions")
             |> api_json(200)
             |> Map.get("data")

    deleted =
      api(ctx.mod, :delete, "/api/v1/moderation/messages/#{ctx.message.id}", %{"reason" => "Spam"})
      |> api_json(200)

    assert deleted["state"] == "deleted" and deleted["body_md"] == "Fixed"

    {:ok, a} = Forum.post_message(ctx.other, ctx.topic, %{"body" => "A"})
    {:ok, b} = Forum.post_message(ctx.other, ctx.topic, %{"body" => "B"})

    assert api(ctx.mod, :post, "/api/v1/moderation/messages/delete", %{
             "topic_id" => ctx.topic.id,
             "message_ids" => [a.id]
           })
           |> api_json(204)

    assert Repo.get!(Message, a.id).deleted_at

    moved =
      api(ctx.mod, :post, "/api/v1/moderation/messages/move", %{
        "message_ids" => [b.id],
        "new" => %{"title" => "Split off", "category_id" => ctx.general.id}
      })
      |> api_json(200)

    assert moved["title"] == "Split off"
    assert Repo.get!(Message, b.id).topic_id == moved["id"]

    assert [%{"id" => _}] =
             api(ctx.mod, :get, "/api/v1/moderation/move-targets?q=Split")
             |> api_json(200)
             |> Map.get("data")
  end

  @tag req: "AP-13"
  test "AP-13 approval queue: approve and reject", ctx do
    {:ok, gated} =
      Forum.create_category(ctx.admin, %{"name" => "Gated", "new_topics" => "approval"})

    {:ok, _} = Forum.update_category(ctx.admin, gated, %{"new_topics" => "approval"})

    pending =
      api(ctx.member_token, :post, "/api/v1/categories/#{gated.id}/topics", %{
        "title" => "Please",
        "body_md" => "Let me in"
      })
      |> api_json(200)

    assert pending["topic"] == nil
    id = pending["pending"]["id"]

    assert [%{"id" => ^id}] =
             api(ctx.member_token, :get, "/api/v1/categories/#{gated.id}/pending")
             |> api_json(200)
             |> Map.get("data")

    assert [%{"id" => ^id}] =
             api(ctx.mod, :get, "/api/v1/moderation/pending-topics")
             |> api_json(200)
             |> Map.get("data")

    approved =
      api(ctx.mod, :post, "/api/v1/moderation/pending-topics/#{id}/approve") |> api_json(200)

    assert approved["topic"]["title"] == "Please"

    second =
      api(ctx.member_token, :post, "/api/v1/categories/#{gated.id}/topics", %{
        "title" => "Again",
        "body_md" => "x"
      })
      |> api_json(200)

    assert api(
             ctx.mod,
             :post,
             "/api/v1/moderation/pending-topics/#{second["pending"]["id"]}/reject",
             %{"reason" => "No"}
           )
           |> api_json(204)

    assert logged?("topic.reject")
  end

  @tag req: "AP-13"
  test "AP-13 members: warn, earlier warnings, ban and lift it; the log", ctx do
    warned =
      api(ctx.mod, :post, "/api/v1/users/#{ctx.other.id}/warn", %{
        "message_id" => ctx.message.id,
        "reason" => "Be kind"
      })
      |> api_json(200)

    assert warned["reason"] == "Be kind"
    assert Accounts.get_user!(ctx.other.id).warning_pending

    assert [%{"reason" => "Be kind"}] =
             api(ctx.mod, :get, "/api/v1/users/#{ctx.other.id}/warnings")
             |> api_json(200)
             |> Map.get("data")

    assert api(ctx.mod, :post, "/api/v1/users/#{ctx.member.id}/warn", %{
             "message_id" => ctx.message.id,
             "reason" => "x"
           })
           |> api_json(403)

    banned =
      api(ctx.mod, :post, "/api/v1/users/#{ctx.other.id}/ban", %{"days" => 7, "reason" => "Spam"})
      |> api_json(200)

    assert banned["banned"]

    assert api(ctx.mod, :post, "/api/v1/users/#{ctx.member.id}/ban", %{"days" => 3})
           |> api_json(422)

    refute api(ctx.mod, :delete, "/api/v1/users/#{ctx.other.id}/ban")
           |> api_json(200)
           |> Map.get("banned")

    log = api(ctx.mod, :get, "/api/v1/moderation/log") |> api_json(200)

    assert Enum.map(log["data"], & &1["action"]) |> Enum.take(3) == [
             "user.unban",
             "user.ban",
             "user.warn"
           ]
  end
end

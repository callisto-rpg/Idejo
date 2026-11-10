# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ChatServiceTest do
  @moduledoc """
  The chat service (steward request, 2026-11-10; `Idejo.Community.Chat`): with
  IDEJO_CHAT_URL, members linked to the provider keep their private conversations there.
  The sidebar's button and the user card lead there, the service reads followed topics and
  copies conversations after a ticket it vouches for, and copied conversations leave the
  forum. Unset, nothing changes.
  """
  use IdejoWeb.ConnCase, async: false

  import Idejo.AccountsFixtures

  alias Idejo.Accounts.UserIdentity
  alias Idejo.Community.Chat
  alias Idejo.{Conversations, Forum, Messages, Reactions, Repo}

  @issuer "https://id.example.test"
  @chat "https://my.example.test/chat"

  setup do
    community = Application.get_env(:idejo, :community)
    oidc = Application.get_env(:idejo, :oidc)

    on_exit(fn ->
      Application.put_env(:idejo, :community, community)

      if oidc,
        do: Application.put_env(:idejo, :oidc, oidc),
        else: Application.delete_env(:idejo, :oidc)

      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Idejo.Messages.OpenMessageSupervisor),
          do: DynamicSupervisor.terminate_child(Idejo.Messages.OpenMessageSupervisor, pid)
    end)

    :ok
  end

  defp chat_on do
    Application.put_env(:idejo, :community,
      url: "http://hub.example.test/internal/community",
      directory_url: nil,
      chat_url: @chat,
      topics_url: "https://my.example.test/topics"
    )

    Application.put_env(:idejo, :oidc,
      issuer: @issuer,
      client_id: "forum-client",
      client_secret: "forum-secret",
      label: "Example ID"
    )
  end

  defp link(user, subject) do
    Repo.insert!(UserIdentity.changeset(%{user_id: user.id, issuer: @issuer, subject: subject}))
    user
  end

  # The service vouches for `ticket` naming `subject` for `scope`; any other is refused.
  defp vouch(tickets) do
    Req.Test.stub(Idejo.Community, fn conn ->
      assert conn.request_path == "/internal/community/chats/tickets"

      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("forum-client:forum-secret")
             ]

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case tickets[JSON.decode!(body)["ticket"]] do
        {subject, scope} -> Req.Test.json(conn, %{"subject" => subject, "scope" => scope})
        nil -> conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "unknown"})
      end
    end)
  end

  @ticket String.duplicate("t", 32)

  test "standalone: the sidebar and the card keep the forum's own conversations", %{conn: conn} do
    ada = user_fixture()
    bo = user_fixture()
    conn = log_in_user(conn, ada)

    html = conn |> get(~p"/u/#{bo.id}") |> html_response(200)
    assert html =~ ~s(action="/u/#{bo.id}/message")
    home = conn |> get(~p"/") |> html_response(200)
    assert home =~ ~s(href="/p")
    refute home =~ "all-topics-sidebar-link"
    assert Chat.start_url(ada, bo) == nil

    # And the service's questions are not answered.
    assert build_conn() |> get("/community/topics?ticket=#{@ticket}") |> json_response(404)
  end

  test "linked members are sent to the chat service; others get no button", %{conn: conn} do
    chat_on()
    Req.Test.stub(Idejo.Community, fn conn -> Req.Test.json(conn, %{"unread" => 2}) end)

    ada = user_fixture() |> link("ada-sub")
    bo = user_fixture() |> link("bo-sub")
    cy = user_fixture()

    conn = log_in_user(conn, ada)
    html = conn |> get(~p"/u/#{bo.id}") |> html_response(200)
    assert html =~ ~s(href="#{@chat}/new?with=bo-sub")
    refute html =~ ~s(action="/u/#{bo.id}/message")

    # Cy has no Idejo ID: no button at all.
    html = conn |> get(~p"/u/#{cy.id}") |> html_response(200)
    refute html =~ "private-message"

    # The sidebar's button leads to the service, with its count.
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(href="#{@chat}" class="sidebar-link" id="conversations-sidebar-link")
    assert Chat.unread(ada) == 2

    # "All my topics" (steward request, 2026-11-10), above Private Conversations.
    assert html =~
             ~s(href="https://my.example.test/topics" class="sidebar-link" id="all-topics-sidebar-link")

    [_, after_topics] = String.split(html, "all-topics-sidebar-link", parts: 2)
    assert after_topics =~ "conversations-sidebar-link"

    # A member not linked keeps the forum's own.
    html = build_conn() |> log_in_user(cy) |> get(~p"/") |> html_response(200)
    assert html =~ ~s(href="/p" class="sidebar-link")
    refute html =~ "all-topics-sidebar-link"
  end

  test "followed topics, for a ticket the service vouches for" do
    chat_on()
    admin = user_with_role_fixture(:administrator)
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    ada = user_fixture() |> link("ada-sub")

    {:ok, topic} =
      Forum.create_topic(ada, general, %{"title" => "Garden plans", "body" => "Tomatoes first"})

    {:ok, _} = Forum.post_message(user_fixture(), topic, %{"body" => "And basil"})
    vouch(%{@ticket => {"ada-sub", "topics"}})

    body = build_conn() |> get("/community/topics?ticket=#{@ticket}") |> json_response(200)
    assert [card] = body["topics"]
    assert card["title"] == "Garden plans"
    assert card["url"] =~ ~r{^https?://[^/]+/t/#{topic.id}/}
    assert card["category"]["name"] == "General"
    assert card["first"] =~ "Tomatoes first"
    assert [%{"text" => "And basil"}] = card["latest"]
    assert card["unread"] == 1

    # The same ticket for another scope, or an unknown one, is refused.
    assert build_conn() |> get("/community/conversations?ticket=#{@ticket}") |> json_response(404)
    other = String.duplicate("u", 32)
    assert build_conn() |> get("/community/topics?ticket=#{other}") |> json_response(404)
  end

  test "conversations between linked members are copied, then leave the forum", %{conn: conn} do
    chat_on()
    ada = user_fixture(%{display_name: "Ada"}) |> link("ada-sub")
    bo = user_fixture(%{display_name: "Bo"}) |> link("bo-sub")
    cy = user_fixture(%{display_name: "Cy"})

    {:ok, with_bo} = Conversations.start(ada, bo)
    {:ok, first} = Messages.commit(ada, with_bo, "Hello **Bo**", break: true)
    {:ok, _} = Messages.commit(bo, with_bo, "Hi Ada", break: true)
    {:ok, _} = Reactions.toggle(bo, first, "smile")
    {:ok, with_cy} = Conversations.start(ada, cy)
    {:ok, _} = Messages.commit(ada, with_cy, "Hello Cy", break: true)

    vouch(%{@ticket => {"ada-sub", "conversations"}})

    body = build_conn() |> get("/community/conversations?ticket=#{@ticket}") |> json_response(200)
    assert body["remaining"] == 1
    assert [conversation] = body["conversations"]
    assert conversation["id"] == with_bo.id
    assert Enum.sort(conversation["subjects"]) == ["ada-sub", "bo-sub"]

    assert [hello, hi] = conversation["messages"]
    assert hello["author"] == "ada-sub" and hello["body_md"] =~ "Hello **Bo**"
    assert hello["body_html"] =~ "<strong>Bo</strong>"
    assert [%{"emoji" => "smile", "char" => "😄", "subject" => "bo-sub"}] = hello["reactions"]
    assert hi["author"] == "bo-sub"

    # Only Ada's own movable conversations are marked, whatever ids are sent.
    moved =
      build_conn()
      |> post("/community/conversations/moved", %{
        "ticket" => @ticket,
        "ids" => [with_bo.id, with_cy.id, Ecto.UUID.generate()]
      })
      |> json_response(200)

    assert moved == %{"moved" => 1}
    assert Enum.map(Conversations.list(ada), & &1.topic.id) == [with_cy.id]
    assert Conversations.get(bo, with_bo.id) == nil
    refute Forum.can_post?(bo, Repo.reload!(with_bo))

    # Its old link leads to the service.
    assert conn |> log_in_user(bo) |> get(~p"/p/#{with_bo.id}") |> redirected_to() == @chat

    # Nothing left to copy.
    body = build_conn() |> get("/community/conversations?ticket=#{@ticket}") |> json_response(200)
    assert body["conversations"] == [] and body["remaining"] == 1
  end
end

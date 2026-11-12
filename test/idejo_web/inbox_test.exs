# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.InboxTest do
  @moduledoc """
  Inbox mode (steward request, 2026-11-10; `Idejo.Inbox`): IDEJO_INBOX=on makes the install
  a group's inbox: Idejo's own header and menus without a sidebar, Forums, Topics and Chats
  tabs, the forums' topics drawn as Idejo's topic rows, chats as private conversations, and
  the forums' old conversations copied in. Off, none of it answers.
  """
  use IdejoWeb.ConnCase, async: false

  import Ecto.Query
  import Idejo.AccountsFixtures

  alias Idejo.Accounts.UserIdentity
  alias Idejo.{Conversations, Inbox, Repo}

  @issuer "https://id.example.test"
  @service "http://hub.example.test/internal/community"

  setup do
    community = Application.get_env(:idejo, :community)
    oidc = Application.get_env(:idejo, :oidc)
    inbox = Application.get_env(:idejo, :inbox)

    on_exit(fn ->
      Application.put_env(:idejo, :community, community)
      Application.put_env(:idejo, :inbox, inbox)

      if oidc,
        do: Application.put_env(:idejo, :oidc, oidc),
        else: Application.delete_env(:idejo, :oidc)
    end)

    :ok
  end

  defp inbox_on do
    Application.put_env(:idejo, :inbox, true)

    Application.put_env(:idejo, :community,
      url: @service,
      directory_url: "https://forums.example.test/",
      chat_url: nil
    )

    Application.put_env(:idejo, :oidc,
      issuer: @issuer,
      client_id: "inbox-client",
      client_secret: "inbox-secret",
      label: "Example ID"
    )
  end

  defp link(user, subject) do
    Repo.insert!(UserIdentity.changeset(%{user_id: user.id, issuer: @issuer, subject: subject}))
    user
  end

  # The group's service: what each path answers (a function of the conn, or a body).
  defp service(answers) do
    Req.Test.stub(Idejo.Community, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("inbox-client:inbox-secret")
             ]

      path = String.replace_prefix(conn.request_path, "/internal/community", "")

      case Map.fetch(answers, path) do
        {:ok, fun} when is_function(fun, 1) -> fun.(conn)
        {:ok, body} -> Req.Test.json(conn, body)
        :error -> conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
      end
    end)
  end

  @topic %{
    "id" => "0192f0c4-0000-7000-8000-000000000001",
    "title" => "Garden plans",
    "slug" => "garden-plans",
    "unread" => 2,
    "message_count" => 5,
    "last_activity_at" => "2026-11-10T10:00:00Z",
    "pinned" => false,
    "state" => "open",
    "topical" => false,
    "author" => %{"display_name" => "Bo", "username" => "bo", "avatar_id" => nil},
    "category" => %{"id" => "c1", "name" => "General", "slug" => "general", "colour" => "#336699"},
    "preview" => %{
      "first" => %{
        "id" => "m0",
        "body_html" => "<p>Tomatoes first</p>",
        "opened_at" => "2026-11-09T10:00:00Z",
        "author" => %{"display_name" => "Bo"}
      },
      "images" => [],
      "latest" => [
        %{
          "id" => "m1",
          "body_html" => "<p>And basil</p>",
          "opened_at" => "2026-11-10T10:00:00Z",
          "author" => %{"display_name" => "Cy"}
        }
      ],
      "participants" => [%{"display_name" => "Bo"}, %{"display_name" => "Cy"}],
      "participant_count" => 2
    }
  }

  test "off: the inbox's pages are not there, and the home page is the forum's", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert conn |> get(~p"/topics") |> response(404)
    assert conn |> get(~p"/chat") |> response(404)
    assert conn |> get(~p"/") |> html_response(200) =~ ~s(id="sidebar")
  end

  test "Forums: Idejo's header and menus, no sidebar, the forums joined", %{conn: conn} do
    inbox_on()
    ada = user_fixture() |> link("ada-sub")

    service(%{
      "" => %{
        "communities" => [%{"name" => "Garden club", "url" => "https://garden.example.test/"}]
      }
    })

    html = conn |> log_in_user(ada) |> get(~p"/") |> html_response(200)
    refute html =~ ~s(id="sidebar")
    refute html =~ ~s(id="sidebar-toggle")
    refute html =~ ~s(id="unread-link")
    assert html =~ ~s(id="community-menu")
    assert html =~ ~s(id="account-menu") or html =~ "account-menu"
    assert html =~ ~s(id="breadcrumb-inbox")
    assert html =~ ~s(id="inbox-tab-forums")
    assert html =~ "Garden club"
    assert html =~ ~s(src="https://garden.example.test/logo")

    # Visitors sign in first.
    assert build_conn() |> get(~p"/") |> redirected_to() == ~p"/users/sign-in"
  end

  test "Topics: the forums' topics as Idejo's own rows, compact or expanded", %{conn: conn} do
    inbox_on()
    ada = user_fixture() |> link("ada-sub")

    service(%{
      "/inbox/topics" => fn conn ->
        assert conn.query_params["subject"] == "ada-sub"

        Req.Test.json(conn, %{
          "forums" => [
            %{
              "name" => "Garden club",
              "url" => "https://garden.example.test/",
              "topics" => [@topic]
            }
          ]
        })
      end
    })

    conn = log_in_user(conn, ada)
    html = conn |> get(~p"/topics?view=compact") |> html_response(200)
    assert html =~ ~s(href="https://garden.example.test/t/#{@topic["id"]}/garden-plans")
    assert html =~ ~s(href="https://garden.example.test/c/general")
    assert html =~ "Garden club" and html =~ "2 new"
    refute html =~ "data-topic-menu=\"#{@topic["id"]}\""
    refute html =~ "Latest messages"

    html = conn |> get(~p"/topics?view=expanded") |> html_response(200)
    assert html =~ "Latest messages" and html =~ "And basil" and html =~ "Tomatoes first"
  end

  test "Topics: the Unread only switch between View and Filter, remembered", %{conn: conn} do
    inbox_on()
    ada = user_fixture() |> link("ada-sub")

    read = %{
      @topic
      | "id" => "0192f0c4-0000-7000-8000-000000000002",
        "title" => "Read already",
        "unread" => 0
    }

    service(%{
      "/inbox/topics" => %{
        "forums" => [
          %{
            "name" => "Garden club",
            "url" => "https://garden.example.test/",
            "topics" => [@topic, read]
          }
        ]
      }
    })

    conn = log_in_user(conn, ada)
    html = conn |> get(~p"/topics?view=compact") |> html_response(200)
    assert html =~ "Garden plans" and html =~ "Read already"
    assert html =~ ~s(id="unread-switch") and html =~ ~s(id="view-toggle")
    assert html =~ ~s(id="forum-filter")
    assert html =~ ~s(role="switch" aria-checked="false") and html =~ "Unread only"
    # Each keeps the other's choice; the switch turns to the other one.
    assert html =~ ~s(href="/topics?show=unread&amp;view=compact")
    assert html =~ ~s(href="/topics?show=all&amp;view=expanded")

    conn = get(conn, ~p"/topics?show=unread")
    html = html_response(conn, 200)
    assert html =~ "Garden plans"
    refute html =~ "Read already"
    assert html =~ ~s(aria-checked="true")
    assert html =~ ~s(href="/topics?show=all&amp;view=compact")

    # Remembered for the next visit.
    html = conn |> recycle() |> get(~p"/topics") |> html_response(200)
    refute html =~ "Read already"

    html = conn |> recycle() |> get(~p"/topics?show=all") |> html_response(200)
    assert html =~ "Read already"
  end

  test "Topics: each card leads with its forum's logo and lists what is new at its right", %{
    conn: conn
  } do
    inbox_on()
    ada = user_fixture() |> link("ada-sub")
    mentioned = Map.merge(@topic, %{"unread" => 2, "mentions" => 1, "reactions" => 0})

    # A forum before the counts (no "mentions", "reactions"): only its new messages.
    older = %{
      @topic
      | "id" => "0192f0c4-0000-7000-8000-000000000003",
        "title" => "Old forum topic",
        "unread" => 1
    }

    reacted = %{
      @topic
      | "id" => "0192f0c4-0000-7000-8000-000000000004",
        "title" => "Quiet",
        "unread" => 0
    }

    reacted = Map.put(reacted, "reactions", 3)

    service(%{
      "/inbox/topics" => %{
        "forums" => [
          %{
            "name" => "Garden club",
            "url" => "https://garden.example.test/",
            "topics" => [mentioned, reacted]
          },
          %{"name" => "Chess", "url" => "https://chess.example.test/", "topics" => [older]}
        ]
      }
    })

    html = conn |> log_in_user(ada) |> get(~p"/topics") |> html_response(200)
    assert html =~ ~s(class="topic-row-forum" aria-hidden="true")
    assert html =~ ~s(src="https://garden.example.test/logo")
    assert html =~ ~s(src="https://chess.example.test/logo")

    lines = fn id ->
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#topic-#{id} .topic-row-activity li")
      |> Enum.map(&String.trim(LazyHTML.text(&1)))
    end

    assert lines.(mentioned["id"]) == ["2 new messages", "1 mention"]
    assert lines.(reacted["id"]) == ["3 reactions"]
    assert lines.(older["id"]) == ["1 new message"]
    # The list replaces the "N new" badge.
    refute html =~ "unread-marker"
  end

  test "Topics: Filter hides the topics of the forums not ticked, remembered", %{conn: conn} do
    inbox_on()
    ada = user_fixture() |> link("ada-sub")
    chess = %{@topic | "id" => "0192f0c4-0000-7000-8000-000000000005", "title" => "Openings"}

    service(%{
      "/inbox/topics" => %{
        "forums" => [
          %{
            "name" => "Garden club",
            "url" => "https://garden.example.test/",
            "topics" => [@topic]
          },
          %{"name" => "Chess", "url" => "https://chess.example.test/", "topics" => [chess]}
        ]
      }
    })

    conn = log_in_user(conn, ada)
    html = conn |> get(~p"/topics?view=compact") |> html_response(200)
    assert html =~ "Garden plans" and html =~ "Openings"
    # Every forum listed, ticked, by name.
    assert html =~ ~s(name="forums[]" value="chess.example.test" checked)
    assert html =~ ~s(name="forums[]" value="garden.example.test" checked)
    refute html =~ ~s(id="forum-filter-hidden")

    conn = get(conn, ~p"/topics?#{[filter: 1, forums: ["garden.example.test"], view: :compact]}")
    html = html_response(conn, 200)
    assert html =~ "Garden plans"
    refute html =~ "Openings"
    assert html =~ "1 hidden"
    refute html =~ ~s(value="chess.example.test" checked)

    # Remembered, also with the switch.
    html = conn |> recycle() |> get(~p"/topics?show=unread") |> html_response(200)
    assert html =~ "Garden plans"
    refute html =~ "Openings"

    # Nothing ticked: no topics, said in words.
    conn = conn |> recycle() |> get(~p"/topics?#{[filter: 1, show: :all]}")
    assert html_response(conn, 200) =~ ~s(id="no-filtered-topics")

    html =
      conn
      |> recycle()
      |> get(~p"/topics?#{[filter: 1, forums: ["garden.example.test", "chess.example.test"]]}")
      |> html_response(200)

    assert html =~ "Garden plans" and html =~ "Openings"
  end

  test "Chats: a forum's Private Message starts the conversation, made for an ID new here", %{
    conn: conn
  } do
    inbox_on()
    ada = user_fixture() |> link("ada-sub")
    service(%{"/profile" => %{"username" => "bo_garden", "picture" => nil}})

    conn = conn |> log_in_user(ada) |> get(~p"/chat/new?with=bo-sub")
    "/p/" <> id = redirected_to(conn)

    bo = Inbox.find_member("bo-sub")
    assert bo.username == "bo_garden"
    assert Conversations.participant?(bo, Conversations.get(ada, id))

    html = build_conn() |> log_in_user(ada) |> get(~p"/p/#{id}") |> html_response(200)
    assert html =~ ~s(href="/chat")
    assert html =~ "Chats"
    assert html =~ ~s(id="composer")

    # Their sign-in later finds that account and gives it their email.
    claimed = Inbox.claim(bo, %{"email" => "bo@example.test", "email_verified" => true})
    assert claimed.email == "bo@example.test"

    # An Idejo ID the provider does not know: refused.
    service(%{})
    conn = build_conn() |> log_in_user(ada) |> get(~p"/chat/new?with=nobody")
    assert redirected_to(conn) == ~p"/chat"
  end

  test "Chats: the forums' conversations are copied once, then marked moved there", %{conn: conn} do
    inbox_on()
    ada = user_fixture() |> link("ada-sub")
    test = self()

    service(%{
      "/profile" => fn conn ->
        Req.Test.json(conn, %{
          "username" => "user_" <> String.replace(conn.query_params["subject"], "-", "_")
        })
      end,
      "/inbox/conversations" => %{
        "forums" => [
          %{
            "name" => "Garden club",
            "host" => "garden.example.test",
            "url" => "https://garden.example.test/p",
            "remaining" => 1,
            "conversations" => [
              %{
                "id" => "c1",
                "subjects" => ["ada-sub", "bo-sub"],
                "messages" => [
                  %{
                    "id" => "m1",
                    "author" => "bo-sub",
                    "body_md" => "Old hello",
                    "body_html" => "<p>Old hello</p><script>x()</script>",
                    "opened_at" => "2026-10-01T09:00:00Z",
                    "reactions" => [%{"emoji" => "smile", "subject" => "ada-sub"}]
                  }
                ]
              }
            ]
          }
        ]
      },
      "/inbox/conversations/moved" => fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:moved, JSON.decode!(body)})
        Req.Test.json(conn, %{"moved" => 1})
      end
    })

    html = conn |> log_in_user(ada) |> get(~p"/chat") |> html_response(200)
    assert html =~ ~s(id="inbox-tab-chats")
    assert html =~ "Garden club" and html =~ "https://garden.example.test/p"

    assert_received {:moved,
                     %{"subject" => "ada-sub", "host" => "garden.example.test", "ids" => ["c1"]}}

    [%{topic: topic, last: last}] = Conversations.list(ada)
    assert last.body_html =~ "Old hello"
    refute last.body_html =~ "script"
    assert topic.message_count == 1

    assert [%{emoji: "smile"}] =
             Repo.all(from r in Idejo.Messages.Reaction, where: r.message_id == ^last.id)

    # Copied once, even asked again.
    Inbox.import(ada, force: true)
    assert [%{topic: %{message_count: 1}}] = Conversations.list(ada)
  end

  test "the group's service asks how many chats have something new, with this server's credentials" do
    inbox_on()
    ada = user_fixture() |> link("ada-sub")
    bo = user_fixture() |> link("bo-sub")
    {:ok, topic} = Conversations.start(bo, ada)
    {:ok, _} = Idejo.Messages.commit(bo, topic, "Hi", break: true)

    ok =
      build_conn()
      |> put_req_header("authorization", "Basic " <> Base.encode64("inbox-client:inbox-secret"))
      |> get("/community/inbox-unread?subject=ada-sub")

    assert json_response(ok, 200) == %{"unread" => 1}

    refused =
      build_conn()
      |> put_req_header("authorization", "Basic " <> Base.encode64("inbox-client:wrong"))
      |> get("/community/inbox-unread?subject=ada-sub")

    assert json_response(refused, 401)
  end
end

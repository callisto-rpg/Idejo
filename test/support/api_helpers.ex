# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ApiHelpers do
  @moduledoc """
  Helpers for API tests (AP-07 to AP-20).

    * `api_token_fixture/2` signs a user in to the app through the real code path (a code
      for a PKCE challenge, then the exchange), and returns the token and its row;
    * `api_conn/2` puts the token on a connection;
    * `api_json/2` asserts the status, then checks the body against the operation's
      documented schema (exactly its top-level keys: none undocumented, every required one)
      and that it holds no email but the user's own (privacy, SP-03).
  """
  import ExUnit.Assertions

  alias Idejo.Accounts.ApiTokens
  alias IdejoWeb.Api.{OpenApi, Operations}

  @doc "A PKCE pair: `{verifier, challenge}`."
  def pkce do
    verifier = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {verifier, :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)}
  end

  @doc "The authorize request's parameters for a challenge."
  def authorize_params(challenge, extra \\ %{}) do
    Map.merge(
      %{
        "response_type" => "code",
        "client_id" => ApiTokens.client_id(),
        "redirect_uri" => ApiTokens.redirect_uri(),
        "scope" => Enum.join(ApiTokens.scopes(), " "),
        "state" => "xyz",
        "code_challenge" => challenge,
        "code_challenge_method" => "S256",
        "device_name" => "Test phone"
      },
      extra
    )
  end

  @doc "Signs `user` in to the app with `scopes`: `{token, row}`."
  def api_token_fixture(user, scopes \\ ApiTokens.scopes()) do
    {verifier, challenge} = pkce()

    {:ok, request} =
      ApiTokens.check_request(authorize_params(challenge, %{"scope" => Enum.join(scopes, " ")}))

    {:ok, code} = ApiTokens.create_code(user, request)

    {:ok, token, row, _user} =
      ApiTokens.exchange(%{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => ApiTokens.redirect_uri(),
        "client_id" => ApiTokens.client_id(),
        "code_verifier" => verifier
      })

    {token, row}
  end

  @doc "The connection with the token as Bearer, asking for JSON."
  def api_conn(conn, token) do
    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)
    |> Plug.Conn.put_req_header("accept", "application/json")
  end

  @doc """
  Asserts the status and returns the decoded body, checked against the operation's schema
  (204: no body) and for other users' emails.
  """
  def api_json(conn, status) do
    assert conn.status == status, "expected #{status}, got #{conn.status}: #{conn.resp_body}"

    if status == 204 do
      assert conn.resp_body == ""
      :no_content
    else
      body = Jason.decode!(conn.resp_body)
      check_privacy(conn, body)

      cond do
        status >= 400 ->
          check(body, "Error")

        op = Operations.find(conn.private[:phoenix_controller], conn.private[:phoenix_action]) ->
          check_response(body, op.response)

        true ->
          :ok
      end

      body
    end
  end

  defp check_response(body, {:page, name}) do
    assert Map.keys(body) |> Enum.sort() == ~w(data next_cursor prev_cursor)
    Enum.each(body["data"], &check(&1, name))
  end

  defp check_response(body, {:list, name}) do
    assert Map.keys(body) == ["data"]
    Enum.each(body["data"], &check(&1, name))
  end

  defp check_response(body, name) when is_binary(name), do: check(body, name)

  @doc "Asserts a map has exactly the schema's keys: no undocumented one, every required one."
  def check(map, name) do
    {properties, required} = OpenApi.schema(name)
    keys = Map.keys(map)

    assert keys -- properties == [],
           "#{name} has undocumented keys: #{inspect(keys -- properties)}"

    assert required -- keys == [], "#{name} lacks required keys: #{inspect(required -- keys)}"
  end

  # SP-03: no response ever holds another user's email; the user's own only about themself.
  defp check_privacy(conn, body) do
    # The token endpoint answers with the user who just signed in, their email included.
    own =
      (conn.assigns[:current_user] && conn.assigns.current_user.email) ||
        (is_map(body) && is_map(body["user"]) && body["access_token"] && body["user"]["email"])

    emails =
      Regex.scan(~r/[A-Za-z0-9._%+-]+@example\.com/, conn.resp_body)
      |> List.flatten()
      |> Enum.uniq()

    assert emails -- List.wrap(own) == [],
           "the response holds other users' emails: #{inspect(emails)}"
  end
end

defmodule IdejoWeb.ApiWorld do
  @moduledoc """
  A small forum for API tests: an administrator, a member, a public category with a topic
  and messages, a category hidden from members with its own topic, message and poll, and a
  private conversation between two other people.
  """
  import Idejo.AccountsFixtures

  alias Idejo.{Access, Conversations, Forum}
  alias Idejo.Messages.Polls

  def build do
    admin = user_with_role_fixture(:administrator)
    member = user_fixture()
    other = user_fixture()
    {:ok, general} = Forum.create_category(admin, %{"name" => "General"})
    {:ok, hidden} = Forum.create_category(admin, %{"name" => "Staff"})

    for role <- Access.list_roles(),
        role.name in ~w(member guest),
        do: {:ok, _} = Access.set_permission(admin, role, hidden, :view, :deny)

    {:ok, topic} =
      Forum.create_topic(other, general, %{"title" => "Garden plans", "body" => "Hello"})

    [opening] = Forum.list_messages(topic)
    {:ok, message} = Forum.post_message(other, topic, %{"body" => "Tomatoes"})

    {:ok, secret} =
      Forum.create_topic(admin, hidden, %{"title" => "Secret", "body" => "Staff only"})

    [secret_opening] = Forum.list_messages(secret)
    {:ok, secret_message} = Forum.post_message(admin, secret, %{"body" => "Hush"})

    {:ok, %{id: secret_poll}} =
      Polls.create(admin, secret_message, %{
        "question" => "Which?",
        "options" => ["A", "B"],
        "hours" => "1"
      })

    third = user_fixture()
    {:ok, conversation} = Conversations.start(other, third)

    %{
      admin: admin,
      member: member,
      other: other,
      general: general,
      hidden: hidden,
      topic: topic,
      opening: opening,
      message: message,
      secret: secret,
      secret_opening: secret_opening,
      secret_message: secret_message,
      secret_poll: secret_poll,
      conversation: conversation
    }
  end
end

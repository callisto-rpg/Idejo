# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Community.Chat do
  @moduledoc """
  The chat service (steward request, 2026-11-10): for an install that belongs to a group of
  communities sharing one sign-in (the community menu's, `Idejo.Community`), members linked
  to the provider (AC-09) hold their private conversations at one place shared by the
  group, not in each forum. Optional and generic: unset, as on a standalone install,
  private conversations stay here (`Idejo.Conversations`) and nothing changes.

  `IDEJO_CHAT_URL` (`config :idejo, :community, chat_url:`), or the `chat_url` a registry
  answers when an administrator connects the server (Admin → Idejo ID), is the service's
  page. With it, for a member linked to the provider:

    * the sidebar's "Private Conversations" leads there (`url/0`), with how many of their
      conversations there have something new (`unread/1`);
    * a user card's "Private Message" leads to `<url>/new?with=<their subject>`
      (`start_url/2`), and only for someone linked too: others get no button;
    * the service asks, for a member it signs in, which topics they follow here and what
      their private conversations here hold, to copy them (`IdejoWeb.ChatServiceController`).

  The service proves who it asks about with a **ticket**: a random word it made for one
  member and one forum. This server hands it back with its OpenID Connect client id and
  secret (HTTP Basic), `POST <api>/tickets` `{"ticket"}` → `{"subject", "scope"}`
  (`check_ticket/1`), so it answers only about the member the service named, and only to the
  service its provider trusts. `<api>` is `<IDEJO_COMMUNITY_URL>/chats`, or
  `<registry>/account/api/chats` for a server connected from Admin → Idejo ID. Two seconds
  at most; any failure is silent (no count, no answer).
  """

  import Ecto.Query

  alias Idejo.Accounts.{OIDC, OIDCRegistry, User, UserIdentity}
  alias Idejo.Repo

  @table __MODULE__
  @ttl :timer.minutes(1)

  @doc "The chat service's page, or nil."
  @spec url() :: String.t() | nil
  def url do
    case (Application.get_env(:idejo, :community) || [])[:chat_url] ||
           OIDCRegistry.config()[:chat_url] do
      "http" <> _ = url -> String.trim_trailing(url, "/")
      _ -> nil
    end
  end

  @doc """
  Where `user` sees the topics they follow across the group ("All my topics" in the sidebar;
  steward request, 2026-11-10): `IDEJO_TOPICS_URL`, or the registry's `topics_url`, for a
  member linked to the provider; else nil.
  """
  @spec topics_url(User.t() | nil) :: String.t() | nil
  def topics_url(user) do
    case (Application.get_env(:idejo, :community) || [])[:topics_url] ||
           OIDCRegistry.config()[:topics_url] do
      "http" <> _ = url -> if subject(user), do: url
      _ -> nil
    end
  end

  @doc """
  The group's Profile and account, where `user` changes settings for all their forums at once
  (steward request, 2026-11-13; `IDEJO_SETTINGS_URL`), for a member linked to the provider;
  else nil.
  """
  @spec settings_url(User.t() | nil) :: String.t() | nil
  def settings_url(user) do
    case (Application.get_env(:idejo, :community) || [])[:settings_url] do
      "http" <> _ = url -> if subject(user), do: url
      _ -> nil
    end
  end

  @doc "Where this server asks the service (tickets, counts), or nil."
  @spec api_url() :: String.t() | nil
  def api_url do
    community = (Application.get_env(:idejo, :community) || [])[:url]

    cond do
      community -> String.trim_trailing(community, "/") <> "/chats"
      registry = OIDCRegistry.config()[:registry_url] -> registry <> "/account/api/chats"
      true -> nil
    end
  end

  @doc """
  Whether `user`'s private conversations live at the chat service: there is one, and they
  are linked to the provider.
  """
  @spec for?(User.t() | nil) :: boolean()
  def for?(nil), do: false
  def for?(%User{} = user), do: url() != nil and subject(user) != nil

  @doc "`user`'s subject at the provider, or nil (not linked, or no provider)."
  @spec subject(User.t() | nil) :: String.t() | nil
  def subject(nil), do: nil

  def subject(%User{id: id}) do
    case OIDC.config() do
      oidc when is_list(oidc) ->
        issuer = oidc[:issuer]

        Repo.one(
          from i in UserIdentity,
            where: i.user_id == ^id and i.issuer == ^issuer,
            select: i.subject,
            limit: 1
        )

      _ ->
        nil
    end
  end

  @doc """
  Where `viewer` starts a conversation with `user` at the chat service: both linked to the
  provider and `Idejo.Conversations.may_message?/2`; else nil.
  """
  @spec start_url(User.t() | nil, User.t()) :: String.t() | nil
  def start_url(viewer, %User{} = user) do
    with base when is_binary(base) <- url(),
         true <- Idejo.Conversations.may_message?(viewer, user),
         mine when is_binary(mine) <- subject(viewer),
         theirs when is_binary(theirs) <- subject(user) do
      base <> "/new?" <> URI.encode_query(%{"with" => theirs})
    else
      _ -> nil
    end
  end

  @doc """
  How many of `user`'s conversations at the chat service have something new: the sidebar's
  count. 0 when it cannot be asked; kept a minute per member.
  """
  @spec unread(User.t() | nil) :: non_neg_integer()
  def unread(user) do
    with true <- for?(user),
         api when is_binary(api) <- api_url(),
         oidc when is_list(oidc) <- OIDC.config() do
      subject = subject(user)

      cached(user.id, fn -> fetch_unread(api, oidc, subject) end)
    else
      _ -> 0
    end
  end

  defp fetch_unread(api, oidc, subject) do
    request = request(api <> "/unread", oidc, params: [subject: subject], receive_timeout: 1_000)

    case Req.get(request) do
      {:ok, %{status: 200, body: %{"unread" => n}}} when is_integer(n) and n >= 0 -> n
      _ -> 0
    end
  end

  @doc """
  The member a ticket from the chat service names, for `scope` (`"topics"`,
  `"conversations"` or `"settings"`): `{:ok, user}` when the service vouches for it and that
  person is a member here; else `:error`.
  """
  @spec check_ticket(term(), String.t()) :: {:ok, User.t()} | :error
  def check_ticket(ticket, scope) when is_binary(ticket) and byte_size(ticket) in 16..128 do
    with api when is_binary(api) <- api_url(),
         oidc when is_list(oidc) <- OIDC.config(),
         {:ok, %{status: 200, body: %{"subject" => subject, "scope" => ^scope}}}
         when is_binary(subject) <-
           Req.post(request(api <> "/tickets", oidc, json: %{ticket: ticket})),
         %User{status: "active"} = user <- user_of(oidc[:issuer], subject) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  def check_ticket(_ticket, _scope), do: :error

  defp user_of(issuer, subject) do
    Repo.one(
      from u in User,
        join: i in UserIdentity,
        on: i.user_id == u.id,
        where: i.issuer == ^issuer and i.subject == ^subject
    )
  end

  defp request(url, oidc, opts) do
    [
      url: url,
      auth: {:basic, oidc[:client_id] <> ":" <> oidc[:client_secret]},
      receive_timeout: 2_000,
      connect_options: [timeout: 2_000],
      retry: false
    ]
    |> Keyword.merge(opts)
    |> Req.new()
    |> Req.merge(Application.get_env(:idejo, :community_req_options, []))
  end

  @doc false
  def child_spec(_arg), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}

  @doc false
  def start_link do
    Agent.start_link(
      fn -> :ets.new(@table, [:named_table, :public, :set, read_concurrency: true]) end,
      name: __MODULE__
    )
  end

  @doc "Forgets the counts kept (a member who just read their conversations)."
  @spec forget(Ecto.UUID.t()) :: :ok
  def forget(user_id) do
    :ets.delete(@table, user_id)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp cached(id, fun) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, id) do
      [{^id, value, at}] when now - at < @ttl ->
        value

      _ ->
        value = fun.()
        :ets.insert(@table, {id, value, now})
        value
    end
  rescue
    ArgumentError -> fun.()
  end
end
